import Foundation
import IOKit
import Darwin

// 注意：SensorSnapshot 定义在 Shared/SensorModels.swift（纯数据、无 IOKit）。
// 本文件（含 IOKit 私有 API）只应由主 App target 编译，Widget 不应包含它。

// MARK: - SMC 通道

/// 通过 AppleSMC 用户客户端读取风扇转速、温度、功率。
/// 关键调用布局由 iStat Menus 7.20 的 -[SMC process:size:key:] 反汇编得到，
/// 并在 Darwin 27 / Apple M1 Pro 上实测通过：
///   IOServiceOpen(selector=1) → 握手 → IOConnectCallStructMethod(conn, 2, in[80], 0x50, out[80])
///   key(FourCC)@0x00, dataSize@0x1c, command@0x2a(data8), 数据@0x30 (float32)
final class SMCSensor {
    private var conn: io_connect_t = 0

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(svc) }
        // selector 必须为 1（AppleSMCClient 的 SMC 接口）；0 是旧式，已失效
        guard IOServiceOpen(svc, mach_task_self_, 1, &conn) == KERN_SUCCESS else { return nil }
        // iStat -[SMC open] 在 IOServiceOpen 之后调用一次空 selector 0 作握手
        IOConnectCallMethod(conn, 0, nil, 0, nil, 0, nil, nil, nil, nil)
    }

    deinit { if conn != IO_OBJECT_NULL { IOServiceClose(conn) } }

    /// FourCC：'F','0','A','c' → 0x46304163（大端字节序写入内存）
    private func fourcc(_ key: String) -> UInt32 {
        var v: UInt32 = 0
        for b in key.utf8.prefix(4) { v = (v << 8) | UInt32(b) }
        return v
    }

    /// 读取一个 SMC key，返回 80 字节输出结构。
    /// command: 5 = READ_BYTES, 8 = READ_INDEX, 9 = READ_KEYINFO
    func raw(_ key: String, command: UInt8 = 5) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: 80)
        var output = [UInt8](repeating: 0, count: 80)
        let k = fourcc(key)
        withUnsafeBytes(of: k) { input.replaceSubrange(0..<4, with: $0) }
        let size: UInt32 = 32
        withUnsafeBytes(of: size) { input.replaceSubrange(0x1c..<0x20, with: $0) }
        input[0x2a] = command
        var outSize = 80
        let kr = IOConnectCallStructMethod(conn, 2, &input, 80, &output, &outSize)
        guard kr == KERN_SUCCESS else { return nil }
        return output
    }

    /// Darwin 27 上 SMC 数值以 little-endian IEEE754 float32 返回。
    func float(_ key: String) -> Double? {
        guard let o = raw(key) else { return nil }
        let bits = UInt32(o[0x30]) | (UInt32(o[0x31]) << 8)
                 | (UInt32(o[0x32]) << 16) | (UInt32(o[0x33]) << 24)
        let f = Float(bitPattern: bits)
        return f.isFinite && f > 0 ? Double(f) : nil
    }

    func uintLE(_ key: String) -> UInt32? {
        guard let o = raw(key) else { return nil }
        return UInt32(o[0x30]) | (UInt32(o[0x31]) << 8)
             | (UInt32(o[0x32]) << 16) | (UInt32(o[0x33]) << 24)
    }

    func uintBE(_ key: String) -> UInt32? {
        guard let o = raw(key) else { return nil }
        return (UInt32(o[0x30]) << 24) | (UInt32(o[0x31]) << 16)
             | (UInt32(o[0x32]) << 8) | UInt32(o[0x33])
    }
}

// MARK: - HID 通道

/// 通过 IOHID EventSystem 私有 API 读取 Apple Silicon PMU 片上测温点。
/// 匹配 AppleVendor 页 (0xff00) 的 TemperatureSensor usage (0x05)，
/// 读取 kIOHIDEventTypeTemperature (=15) 事件的浮点值。
final class HIDTemperatureSensor {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchFn = @convention(c) (OpaquePointer, CFDictionary) -> Void
    private typealias CopySvcFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int64) -> Double
    private typealias CopyPropFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<AnyObject>?

    private let handle: UnsafeMutableRawPointer
    /// 强持有 IOHIDEventSystemClient 对象本身：它一旦被 ARC 释放，
    /// 之后所有调用都会在 IOMIGMachPortGetPort 里空指针崩溃。
    private let clientObject: AnyObject
    private var client: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(clientObject).toOpaque())
    }
    private let services: CFArray
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn

    init?() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        handle = h
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let create: CreateFn = sym("IOHIDEventSystemClientCreate"),
              let setMatch: SetMatchFn = sym("IOHIDEventSystemClientSetMatching"),
              let copySvc: CopySvcFn = sym("IOHIDEventSystemClientCopyServices"),
              let ce: CopyEventFn = sym("IOHIDServiceClientCopyEvent"),
              let gf: GetFloatFn = sym("IOHIDEventGetFloatValue")
        else { return nil }
        copyEvent = ce; getFloat = gf

        guard let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        clientObject = c
        let cptr = UnsafeRawPointer(Unmanaged.passUnretained(c).toOpaque())
        let dict: CFDictionary = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x05] as CFDictionary
        setMatch(OpaquePointer(cptr), dict)
        guard let s = copySvc(OpaquePointer(cptr))?.takeRetainedValue() else { return nil }
        services = s
    }

    // 注意：client / services / event 都是 IOHIDEventSystem 内部持有的对象，
    // 我们只借用其指针（takeUnretainedValue），绝不能让 ARC 或手动 CFRelease 释放，
    // 否则会在 IOHIDEventSystemClientTerminationCallback 里二次释放导致 EXC_BREAKPOINT。
    // 因此这里故意不做额外 release，也不 dlclose（进程生命周期内保持有效）。

    func read() -> [(name: String, celsius: Double)] {
        let count = CFArrayGetCount(services)
        var result: [(String, Double)] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let svc = UnsafeRawPointer(raw)
            guard let ev = copyEvent(svc, 15, 0, 0)?.takeUnretainedValue() else { continue }
            let evPtr = UnsafeRawPointer(Unmanaged.passUnretained(ev as AnyObject).toOpaque())
            var t = 0.0
            for f in 0..<8 {
                let v = getFloat(evPtr, Int64((15 << 16) | Int64(f)))
                if v > 1 && v < 130 && v > t { t = v }
            }
            if t > 0 { result.append(("PMU", t)) }
        }
        return result
    }
}

// MARK: - 聚合读取器

/// 把 SMC + HID 两路数据合并成一份快照。
enum SensorReader {
    static func snapshot() -> SensorSnapshot {
        var s = SensorSnapshot()

        if let smc = SMCSensor() {
            s.smcKeyCount = Int(smc.uintBE("#KEY") ?? 0)
            s.fanCount = Int(smc.uintLE("FNum") ?? 0)
            s.fan0RPM = smc.float("F0Ac") ?? 0
            s.fan1RPM = smc.float("F1Ac") ?? 0
            s.fan0Target = smc.float("F0Tg") ?? 0
            s.fan1Target = smc.float("F1Tg") ?? 0
            s.cpuTemp = smc.float("Tp0C") ?? 0
            s.cpuTempMax = smc.float("Tp0P") ?? 0
            s.batteryTemp = smc.float("TB0T") ?? 0
            s.powerWatt = smc.float("PSTR") ?? 0
            s.available = s.fanCount > 0
        }

        if let hid = HIDTemperatureSensor() {
            let temps = hid.read()
            let values = temps.map(\.celsius)
            s.hidSensorCount = values.count
            if let mx = values.max(), let sum = Optional(values.reduce(0, +)), !values.isEmpty {
                s.socTempMax = mx
                s.socTempAvg = sum / Double(values.count)
                s.available = true
            }
        }
        return s
    }
}
