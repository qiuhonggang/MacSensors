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
        let snap = SensorStore.load() ?? .placeholder
        completion(SensorEntry(date: Date(), snapshot: context.isPreview ? .placeholder : snap))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SensorEntry>) -> Void) {
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
        case .systemSmall:  SmallWidget(s: s)
        case .systemMedium: MediumWidget(s: s)
        default:            LargeWidget(s: s)
        }
    }
}

// MARK: - 小尺寸：核心温度 + 状态色 + 风扇档位

struct SmallWidget: View {
    let s: SensorSnapshot
    var body: some View {
        let level = s.overallLevel
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: level.symbol).foregroundStyle(level.color)
                Text("芯片温度").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(level.title).font(.caption2.weight(.semibold))
                    .foregroundStyle(level.color)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", s.socTempMax))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.7)
                    .foregroundStyle(level.color)
                Text("°C").font(.title3).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // 风扇条：档位 + 百分比，不再是裸 RPM
            HStack(spacing: 6) {
                Image(systemName: "fan.fill").font(.caption2).foregroundStyle(s.fan0.level.color)
                Text(s.fan0.stage).font(.caption2.weight(.semibold))
                    .foregroundStyle(s.fan0.level.color)
                Spacer()
                Text(String(format: "%.0f%%", s.fan0.fraction * 100))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            WidgetGauge(fraction: s.fan0.fraction, color: s.fan0.level.color)
            Text(String(format: "%.1f W · 平均 %.1f°", s.powerWatt, s.socTempAvg))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 中尺寸：四宫格（带状态色）

struct MediumWidget: View {
    let s: SensorSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MacSensors", systemImage: "thermometer.sun.fill").font(.headline)
                Spacer()
                Text(s.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Tile(icon: "cpu.fill", title: "芯片", value: s.socTempMax, unit: "°C",
                     level: s.overallLevel)
                Tile(icon: "flame.fill", title: "CPU", value: s.cpuTempMax, unit: "°C",
                     level: TempLevel.of(s.cpuTempMax))
                Tile(icon: "fan.fill", title: "风扇0", value: s.fan0RPM, unit: "RPM",
                     level: s.fan0.level, digits: 0)
                Tile(icon: "bolt.fill", title: "功率", value: s.powerWatt, unit: "W",
                     level: .normal)
            }
            // 风扇档位条
            HStack(spacing: 6) {
                Image(systemName: "fan.fill").font(.caption2).foregroundStyle(s.fan0.level.color)
                Text("风扇 \(s.fan0.stage)").font(.caption2).foregroundStyle(.secondary)
                WidgetGauge(fraction: s.fan0.fraction, color: s.fan0.level.color)
                Text(String(format: "%.0f%%", s.fan0.fraction * 100))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text(String(format: "平均 %.1f° · 最低 %.1f° · 风扇1 %.0f RPM",
                            s.socTempAvg, s.socTempMin, s.fan1RPM))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 大尺寸：完整仪表盘 + 额外温度点

struct LargeWidget: View {
    let s: SensorSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("MacSensors · 硬件监控", systemImage: s.overallLevel.symbol)
                    .font(.headline).foregroundStyle(s.overallLevel.color)
                Spacer()
                Text(s.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Tile(icon: "cpu.fill", title: "芯片最高", value: s.socTempMax, unit: "°C",
                     level: s.overallLevel)
                Tile(icon: "flame.fill", title: "CPU 核心", value: s.cpuTempMax, unit: "°C",
                     level: TempLevel.of(s.cpuTempMax))
                Tile(icon: "thermometer", title: "平均", value: s.socTempAvg, unit: "°C",
                     level: TempLevel.of(s.socTempAvg))
            }

            // 风扇可视化
            VStack(alignment: .leading, spacing: 6) {
                Text("风扇").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("风扇0 · \(s.fan0.stage)").font(.caption2)
                        .foregroundStyle(s.fan0.level.color).frame(width: 82, alignment: .leading)
                    WidgetGauge(fraction: s.fan0.fraction, color: s.fan0.level.color)
                    Text(String(format: "%.0f%%", s.fan0.fraction * 100))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                if s.fanCount > 1 {
                    HStack(spacing: 8) {
                        Text("风扇1 · \(s.fan1.stage)").font(.caption2)
                            .foregroundStyle(s.fan1.level.color).frame(width: 82, alignment: .leading)
                        WidgetGauge(fraction: s.fan1.fraction, color: s.fan1.level.color)
                        Text(String(format: "%.0f%%", s.fan1.fraction * 100))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            Divider()

            // 更多温度检测点（分组，最多 6 行）
            Text("温度检测点").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let rows = Array(s.tempPoints.sorted { $0.celsius > $1.celsius }.prefix(6))
            ForEach(rows) { p in
                HStack(spacing: 5) {
                    Circle().fill(TempLevel.of(p.celsius).color).frame(width: 6, height: 6)
                    Text(p.label).font(.caption).lineLimit(1)
                    Text(p.group).font(.caption2).foregroundStyle(.quaternary)
                    Spacer()
                    Text(String(format: "%.1f°", p.celsius))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(TempLevel.of(p.celsius).color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 复用小组件

/// Widget 内的仪表条（与 App 内 GaugeBar 相同，但保持 target 独立）
struct WidgetGauge: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}

struct Tile: View {
    let icon: String
    let title: String
    let value: Double
    let unit: String
    let level: TempLevel
    var digits: Int = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.\(digits)f", value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6)
                    .foregroundStyle(level.color)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Image(systemName: level.symbol).font(.caption2)
                Text(level.title).font(.caption2)
            }
            .foregroundStyle(level.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
        .description("彩色温度分级、风扇档位与更多片上测温点")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
