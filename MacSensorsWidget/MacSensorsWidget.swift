import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct SensorEntry: TimelineEntry {
    let date: Date
    let snapshot: SensorSnapshot
}

// MARK: - Provider

struct SensorProvider: TimelineProvider {
    func placeholder(in context: Context) -> SensorEntry {
        SensorEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SensorEntry) -> Void) {
        // Widget 库预览 / 添加时展示：只读共享快照。
        // 绝不在此现场采样 —— Widget 在沙箱内，IOKit/SMC 私有 API 会被拒绝，
        // 且本 target 根本不编译 SensorReader（编译期即杜绝）。
        let snap = SensorStore.load() ?? .placeholder
        completion(SensorEntry(date: Date(), snapshot: context.isPreview ? .placeholder : snap))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SensorEntry>) -> Void) {
        // 主 App 每 5 秒写一次共享快照；Widget 时间线每 ~1 分钟刷新一次读取。
        // 同样只读共享数据，不在沙箱内采集硬件。
        let snap = SensorStore.load() ?? .placeholder
        let entry = SensorEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget 视图（按尺寸自适应）

struct SensorWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SensorEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .systemSmall:
            SmallWidget(s: s)
        case .systemMedium:
            MediumWidget(s: s)
        default:
            LargeWidget(s: s)
        }
    }
}

// MARK: - 小尺寸：核心温度 + 风扇

struct SmallWidget: View {
    let s: SensorSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "thermometer.medium").foregroundStyle(.orange)
                Text("芯片温度").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", s.socTempMax))
                    .font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("°C").font(.title3).foregroundStyle(.secondary)
            }
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label(String(format: "%.0f", s.fan0RPM), systemImage: "fan")
                Label(String(format: "%.0f W", s.powerWatt), systemImage: "bolt.fill")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 中尺寸：四宫格

struct MediumWidget: View {
    let s: SensorSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MacSensors", systemImage: "thermometer.sun.fill").font(.headline)
                Spacer()
                Text(s.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Tile(icon: "cpu.fill", title: "芯片", value: s.socTempMax, unit: "°C", color: .orange)
                Tile(icon: "flame.fill", title: "CPU", value: s.cpuTempMax, unit: "°C", color: .red)
                Tile(icon: "fan.fill", title: "风扇0", value: s.fan0RPM, unit: "RPM", color: .blue, digits: 0)
                Tile(icon: "bolt.fill", title: "功率", value: s.powerWatt, unit: "W", color: .green)
            }
            HStack {
                Text(String(format: "平均 %.1f°C · 风扇1 %.0f RPM", s.socTempAvg, s.fan1RPM))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 大尺寸：完整仪表盘

struct LargeWidget: View {
    let s: SensorSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MacSensors · 硬件监控", systemImage: "thermometer.sun.fill").font(.headline)
                Spacer()
                Text(s.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Tile(icon: "cpu.fill", title: "芯片最高", value: s.socTempMax, unit: "°C", color: .orange)
                Tile(icon: "flame.fill", title: "CPU 核心", value: s.cpuTempMax, unit: "°C", color: .red)
                Tile(icon: "thermometer", title: "平均", value: s.socTempAvg, unit: "°C", color: .yellow)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Info(icon: "fan", label: "风扇 0", value: String(format: "%.0f RPM", s.fan0RPM))
                    Info(icon: "fan", label: "风扇 1", value: String(format: "%.0f RPM", s.fan1RPM))
                }
                GridRow {
                    Info(icon: "bolt.fill", label: "系统功率", value: String(format: "%.1f W", s.powerWatt))
                    Info(icon: "battery.100", label: "电池温度", value: String(format: "%.1f °C", s.batteryTemp))
                }
                GridRow {
                    Info(icon: "square.grid.2x2", label: "SMC keys", value: "\(s.smcKeyCount)")
                    Info(icon: "circle.grid.2x2", label: "HID 测温点", value: "\(s.hidSensorCount)")
                }
            }
            .font(.callout)
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 复用小组件

struct Tile: View {
    let icon: String
    let title: String
    let value: Double
    let unit: String
    let color: Color
    var digits: Int = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.\(digits)f", value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Info: View {
    let icon: String
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

// MARK: - Widget 定义

@main
struct MacSensorsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacSensorsWidget()
    }
}

struct MacSensorsWidget: Widget {
    let kind = "MacSensorsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SensorProvider()) { entry in
            SensorWidgetView(entry: entry)
        }
        .configurationDisplayName("MacSensors")
        .description("实时显示芯片温度、风扇转速与系统功率")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
