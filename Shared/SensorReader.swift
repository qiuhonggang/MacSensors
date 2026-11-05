import Foundation
import IOKit
import Darwin

// 注意：SensorSnapshot / TempPoint 定义在 Shared/SensorModels.swift（纯数据、无 IOKit）。
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

// MARK: - SMC 温度 key 表

/// 尽可能覆盖 Apple Silicon / Intel 常见 SMC 温度键。
/// 不存在的 key 会返回 nil，自动跳过，不影响其它机型。
/// (key, 显示名, 分组)
private let smcTempKeys: [(String, String, String)] = [
    // CPU / 核心
    ("Tp0C", "CPU 性能核", "CPU"),
    ("Tp0P", "CPU 性能核最高", "CPU"),
    ("Tp1C", "CPU 能效核", "CPU"),
    ("Tp1P", "CPU 能效核最高", "CPU"),
    ("Tp2P", "CPU 核心 2", "CPU"),
    ("Tp3P", "CPU 核心 3", "CPU"),
    ("Tp4P", "CPU 核心 4", "CPU"),
    ("Tp5P", "CPU 核心 5", "CPU"),
    ("TC0C", "CPU 核心 0", "CPU"),
    ("TC1C", "CPU 核心 1", "CPU"),
    ("TC2C", "CPU 核心 2", "CPU"),
    ("TC3C", "CPU 核心 3", "CPU"),
    ("TC0P", "CPU 接近度", "CPU"),
    ("TCAD", "CPU 二极管", "CPU"),
    // GPU
    ("Tg0P", "GPU 最高", "GPU"),
    ("Tg0C", "GPU 核心", "GPU"),
    ("Tg1P", "GPU 接近度", "GPU"),
    ("TG0P", "GPU 接近度", "GPU"),
    ("TG0D", "GPU 二极管", "GPU"),
    // 片上 / SoC
    ("Ts0P", "SoC 接近度 0", "芯片"),
    ("Ts1P", "SoC 接近度 1", "芯片"),
    ("Ts0S", "SoC 表面", "芯片"),
    ("Tm0P", "内存控制器", "内存"),
    ("Tm1P", "内存控制器 1", "内存"),
    ("Tm2P", "内存控制器 2", "内存"),
    ("Tm0S", "内存模块", "内存"),
    ("TL0P", "显示引擎", "芯片"),
    ("TI0P", "雷电控制器", "芯片"),
    // 电池
    ("TB0T", "电池温度 1", "电池"),
    ("TB1T", "电池温度 2", "电池"),
    ("TB2T", "电池温度 3", "电池"),
    ("TB0V", "电池电压", "电源"),
    ("B0AV", "电池电压", "电源"),
    // 机身 / 外壳 / 环境
    ("Ta0P", "环境传感器", "机身"),
    ("Ta1P", "环境传感器 1", "机身"),
    ("Ta0S", "机身表面", "机身"),
    ("Th0P", "散热片", "机身"),
    ("Th1P", "散热片 1", "机身"),
    ("TW0P", "无线模块", "机身"),
    ("Tl0P", "掌托", "机身"),
    ("Ts0D", "机身表面", "机身"),
    // 电源 / 充电
    ("TP0P", "电源管理器", "电源"),
    ("TP1P", "电源管理器 1", "电源"),
    ("TPCD", "充电控制器", "电源"),
    ("TTF0", "变压器", "电源"),
    ("TCSA", "电源适配器", "电源")
]

// MARK: - HID 通道

/// 通过 IOHID EventSystem 私有 API 读取 Apple Silicon PMU 片上测温点。
final class HIDTemperatureSensor {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchFn = @convention(c) (OpaquePointer, CFDictionary) -> Void
    private typealias CopySvcFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int64) -> Double
    private typealias CopyPropFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<AnyObject>?

    private let handle: UnsafeMutableRawPointer
    /// 强持有 IOHIDEventSystemClient 对象本身：一旦被 ARC 释放，
    /// 之后所有调用都会在 IOMIGMachPortGetPort 里空指针崩溃。
    private let clientObject: AnyObject
    private var client: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(clientObject).toOpaque())
    }
    private let services: CFArray
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let copyProp: CopyPropFn?

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
        copyProp = sym("IOHIDServiceClientCopyProperty")

        guard let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        clientObject = c
        let cptr = UnsafeRawPointer(Unmanaged.passUnretained(c).toOpaque())
        let dict: CFDictionary = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x05] as CFDictionary
        setMatch(OpaquePointer(cptr), dict)
        guard let s = copySvc(OpaquePointer(cptr))?.takeRetainedValue() else { return nil }
        services = s
    }

    /// 返回每个 HID 测温服务的读数，并尽量带上系统的命名。
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
            guard t > 0 else { continue }

            var label = "PMU \(i + 1)"
            if let cp = copyProp,
               let prop = cp(svc, "Product" as CFString)?.takeUnretainedValue() as? String,
               !prop.isEmpty {
                label = prop
            }
            result.append((label, t))
        }
        return result
    }
}

// MARK: - 聚合读取器

enum SensorReader {
    static func snapshot() -> SensorSnapshot {
        var s = SensorSnapshot()
        var points: [TempPoint] = []

        if let smc = SMCSensor() {
            s.smcKeyCount = Int(smc.uintBE("#KEY") ?? 0)
            s.fanCount = Int(smc.uintLE("FNum") ?? 0)
            s.fan0RPM = smc.float("F0Ac") ?? 0
            s.fan1RPM = smc.float("F1Ac") ?? 0
            s.fan0Target = smc.float("F0Tg") ?? 0
            s.fan1Target = smc.float("F1Tg") ?? 0
            s.fan0Max = smc.float("F0Mx") ?? 5500
            s.fan1Max = smc.float("F1Mx") ?? 5500
            s.fan0Min = smc.float("F0Mn") ?? 0
            s.fan1Min = smc.float("F1Mn") ?? 0
            s.cpuTemp = smc.float("Tp0C") ?? 0
            s.cpuTempMax = smc.float("Tp0P") ?? 0
            s.batteryTemp = smc.float("TB0T") ?? 0
            s.powerWatt = smc.float("PSTR") ?? 0
            s.available = s.fanCount > 0

            // 遍历温度 key 表：存在的才收录，自动适配不同机型
            for (key, label, group) in smcTempKeys {
                if let v = smc.float(key), v > 1, v < 130 {
                    points.append(TempPoint(key: key, label: label,
                                            celsius: v, group: group, source: "SMC"))
                }
            }
        }

        if let hid = HIDTemperatureSensor() {
            let temps = hid.read()
            let values = temps.map(\.celsius)
            s.hidSensorCount = values.count
            if !values.isEmpty {
                let sum = values.reduce(0, +)
                s.socTempMax = values.max() ?? 0
                s.socTempAvg = sum / Double(values.count)
                s.socTempMin = values.min() ?? 0
                s.available = true

                // HID 63 个测温点全部列出，但按温度排序后只把「热点前 8」
                // 放进命名列表，避免下拉面板过长；详情窗口可见完整统计。
                let sorted = temps.sorted { $0.celsius > $1.celsius }
                for (i, t) in sorted.prefix(8).enumerated() {
                    points.append(TempPoint(key: "HID-\(i)", label: t.name,
                                            celsius: t.celsius,
                                            group: "片上测温点(HID)", source: "HID"))
                }
            }
        }

        s.tempPoints = points
        return s
    }
}
