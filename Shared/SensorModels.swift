import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - 命名温度点

/// 一个带名称、分组、来源的温度读数。
/// 下拉面板与详情窗口按 group 分区展示，比裸数字直观得多。
struct TempPoint: Codable, Sendable, Equatable, Identifiable {
    var id: String { key }
    var key: String            // SMC FourCC 或 HID 标识
    var label: String          // 中文可读名
    var celsius: Double
    var group: String          // 「芯片 / CPU / GPU / 内存 / 电池 / 机身 / 电源 / 片上」
    var source: String         // "SMC" / "HID"
}

// MARK: - 温度 / 风扇分级

/// 统一的温度状态分级。视图层只消费这个，不各自写阈值。
enum TempLevel: String, Codable, Sendable {
    case cool, normal, warm, hot, critical

    /// 按半导体常见结温划分：偏保守，兼顾 Apple Silicon 实测区间。
    static func of(_ c: Double) -> TempLevel {
        if c <= 0     { return .normal }
        if c < 45     { return .cool }
        if c < 62     { return .normal }
        if c < 75     { return .warm }
        if c < 90     { return .hot }
        return .critical
    }

    var title: String {
        switch self {
        case .cool:     return "凉爽"
        case .normal:   return "正常"
        case .warm:     return "偏热"
        case .hot:      return "较热"
        case .critical: return "高温"
        }
    }

    var symbol: String {
        switch self {
        case .cool:     return "snowflake"
        case .normal:   return "checkmark.circle.fill"
        case .warm:     return "thermometer.medium"
        case .hot:      return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    #if canImport(SwiftUI)
    var color: Color {
        switch self {
        case .cool:     return .cyan
        case .normal:   return .green
        case .warm:     return .yellow
        case .hot:      return .orange
        case .critical: return .red
        }
    }
    #endif
}

/// 风扇状态：把「转速 / 目标 / 上限」换算成百分比与文字档位。
struct FanStatus: Codable, Sendable, Equatable {
    var rpm: Double = 0
    var target: Double = 0
    var maximum: Double = 0       // SMC F0Mx / F1Mx，读不到时回落 5500
    var minimum: Double = 0       // SMC F0Mn / F1Mn

    /// 占最大转速的百分比（0...1）
    var fraction: Double {
        let maxV = maximum > 0 ? maximum : 5500
        guard rpm > 0 else { return 0 }
        return min(max(rpm / maxV, 0), 1)
    }

    /// 显示用的档位文字
    var stage: String {
        guard rpm > 0 else { return "停转" }
        switch fraction {
        case ..<0.20: return "静音"
        case ..<0.40: return "低速"
        case ..<0.60: return "中速"
        case ..<0.80: return "高速"
        default:      return "满载"
        }
    }

    /// 风扇也用温度那套色阶，便于一眼看出负载
    var level: TempLevel {
        switch fraction {
        case ..<0.20: return .cool
        case ..<0.40: return .normal
        case ..<0.60: return .warm
        case ..<0.80: return .hot
        default:      return .critical
        }
    }
}

// MARK: - 快照

/// 一次完整采样。纯数据模型，无任何 IOKit / 私有 API 依赖，
/// 因此主 App 与 Widget Extension 都可安全编译。
struct SensorSnapshot: Codable, Sendable, Equatable {
    var date: Date = Date()
    var cpuTemp: Double = 0
    var cpuTempMax: Double = 0
    var socTempMax: Double = 0
    var socTempAvg: Double = 0
    var socTempMin: Double = 0       // HID 全机最低
    var batteryTemp: Double = 0
    var fan0RPM: Double = 0
    var fan1RPM: Double = 0
    var fan0Target: Double = 0
    var fan1Target: Double = 0
    var fan0Max: Double = 0
    var fan1Max: Double = 0
    var fan0Min: Double = 0
    var fan1Min: Double = 0
    var fanCount: Int = 0
    var smcKeyCount: Int = 0
    var powerWatt: Double = 0
    var hidSensorCount: Int = 0
    var available: Bool = false

    /// 所有命名温度点（下拉列表 / 详情表格的数据源）
    var tempPoints: [TempPoint] = []

    var fan0: FanStatus {
        FanStatus(rpm: fan0RPM, target: fan0Target, maximum: fan0Max, minimum: fan0Min)
    }
    var fan1: FanStatus {
        FanStatus(rpm: fan1RPM, target: fan1Target, maximum: fan1Max, minimum: fan1Min)
    }

    /// 下拉面板顶部的主状态
    var overallLevel: TempLevel { TempLevel.of(socTempMax) }

    /// 按分组整理温度点，组内按温度降序
    var groupedTemps: [(group: String, points: [TempPoint])] {
        let order = ["芯片", "CPU", "GPU", "片上热点", "内存", "电池", "机身", "电源", "其他"]
        var buckets: [String: [TempPoint]] = [:]
        for p in tempPoints where p.celsius > 0 {
            buckets[p.group, default: []].append(p)
        }
        return order.compactMap { g in
            guard let pts = buckets[g], !pts.isEmpty else { return nil }
            return (g, pts.sorted { $0.celsius > $1.celsius })
        }
    }

    static var empty: SensorSnapshot { SensorSnapshot() }

    static var placeholder: SensorSnapshot {
        var s = SensorSnapshot()
        s.available = true
        s.socTempMax = 54.2
        s.socTempAvg = 49.8
        s.socTempMin = 41.3
        s.cpuTempMax = 63.1
        s.fan0RPM = 2400; s.fan1RPM = 2600
        s.fan0Max = 5500; s.fan1Max = 5500
        s.fan0Min = 1000; s.fan1Min = 1000
        s.fan0Target = 2400; s.fan1Target = 2600
        s.fanCount = 2
        s.powerWatt = 22.5
        s.tempPoints = [
            TempPoint(key: "Tp0P", label: "性能核最高", celsius: 63.1, group: "CPU", source: "SMC"),
            TempPoint(key: "Tg0P", label: "GPU 最高", celsius: 55.4, group: "GPU", source: "SMC"),
            TempPoint(key: "HID", label: "片上热点", celsius: 54.2, group: "片上热点", source: "HID")
        ]
        return s
    }
}
