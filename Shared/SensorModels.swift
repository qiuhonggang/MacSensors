import Foundation

/// 一次完整采样。纯数据模型，无任何 IOKit / 私有 API 依赖，
/// 因此主 App 与 Widget Extension 都可安全编译。
/// 可 Codable 以便通过 App Group 共享。
struct SensorSnapshot: Codable, Sendable, Equatable {
    var date: Date = Date()
    var cpuTemp: Double = 0          // SMC Tp0C / 性能核
    var cpuTempMax: Double = 0       // SMC Tp0P（最热核心）
    var socTempMax: Double = 0       // HID PMU 全机最高
    var socTempAvg: Double = 0       // HID PMU 平均
    var batteryTemp: Double = 0      // SMC TB0T
    var fan0RPM: Double = 0          // SMC F0Ac
    var fan1RPM: Double = 0          // SMC F1Ac
    var fan0Target: Double = 0       // SMC F0Tg
    var fan1Target: Double = 0       // SMC F1Tg
    var fanCount: Int = 0            // SMC FNum
    var smcKeyCount: Int = 0
    var powerWatt: Double = 0        // SMC PSTR
    var hidSensorCount: Int = 0
    var available: Bool = false

    static var empty: SensorSnapshot { SensorSnapshot() }

    /// 组件在没有共享数据时的占位内容（避免显示全 0）。
    /// 注意：这是纯静态值，不触发任何硬件采集。
    static var placeholder: SensorSnapshot {
        var s = SensorSnapshot()
        s.available = true
        s.socTempMax = 54.2
        s.socTempAvg = 49.8
        s.cpuTempMax = 63.1
        s.fan0RPM = 2400
        s.fan1RPM = 2600
        s.fanCount = 2
        s.powerWatt = 22.5
        return s
    }
}
