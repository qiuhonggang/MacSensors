import SwiftUI
import AppKit
import WidgetKit

// MARK: - 定时采样模型

@MainActor
final class SensorModel: ObservableObject {
    @Published var snapshot: SensorSnapshot = .empty
    @Published var history: [Double] = []
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let snap = SensorReader.snapshot()
            await MainActor.run {
                self.snapshot = snap
                self.history.append(snap.socTempMax)
                if self.history.count > 40 { self.history.removeFirst() }
                SensorStore.save(snap)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    var menuTitle: String {
        guard snapshot.available else { return "—" }
        return String(format: "%.0f°", snapshot.socTempMax)
    }
}

// MARK: - App 入口

@main
struct MacSensorsApp: App {
    @StateObject private var model = SensorModel()
    @Environment(\.openWindow) private var openWindow

    private func openDetail() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "detail")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for window in NSApp.windows where window.title == "MacSensors 详情" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model, openDetail: openDetail)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(model.snapshot.overallLevel.color)
                Text(model.menuTitle)
                    .foregroundStyle(model.snapshot.overallLevel.color)
            }
        }
        // .window 才能自定义字体/颜色/布局；.menu 是系统 NSMenu，只能是灰字
        .menuBarExtraStyle(.window)

        Window("MacSensors 详情", id: "detail") {
            DetailView(model: model)
        }
        .defaultSize(width: 520, height: 660)
    }
}

// MARK: - 彩色数值 / 徽章（下拉与详情共用）

/// 大号彩色数值：颜色直接反映冷热，不再是灰色
struct ColoredValue: View {
    let value: Double
    let unit: String
    let digits: Int
    let level: TempLevel
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%.\(digits)f", value))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(level.color)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: level.symbol)
                .font(.caption2)
                .foregroundStyle(level.color)
        }
    }
}

/// 状态徽章：一眼看出「正常 / 偏热 / 高温」
struct LevelBadge: View {
    let level: TempLevel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbol)
            Text(level.title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(level.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(level.color.opacity(0.15), in: Capsule())
    }
}

/// 横向仪表条：给风扇/功率一个相对量，比裸 RPM 直观
struct GaugeBar: View {
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
        .frame(height: 6)
    }
}

/// 风扇行：转速 + 档位 + 占最大转速百分比 + 仪表条
struct FanRow: View {
    let name: String
    let fan: FanStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(name, systemImage: "fan.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(fan.stage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(fan.level.color)
                Spacer()
                Text(String(format: "%.0f RPM", fan.rpm))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(fan.level.color)
                Text(String(format: "· %.0f%%", fan.fraction * 100))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GaugeBar(fraction: fan.fraction, color: fan.level.color)
            if fan.target > 0 {
                Text(String(format: "目标 %.0f / 上限 %.0f RPM", fan.target, fan.maximum > 0 ? fan.maximum : 5500))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 菜单栏下拉内容

struct MenuContentView: View {
    @ObservedObject var model: SensorModel
    let openDetail: () -> Void

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：主温度 + 状态徽章 + 传感器计数
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.title2)
                    .foregroundStyle(s.overallLevel.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacSensors").font(.headline)
                    Text("Apple Silicon · 实时监测")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                LevelBadge(level: s.overallLevel)
            }

            if s.available {
                // 主读数区：彩色大数字
                HStack(alignment: .firstTextBaseline) {
                    ColoredValue(value: s.socTempMax, unit: "°C", digits: 1,
                                 level: s.overallLevel, size: 34)
                    Text("芯片最高").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "平均 %.1f°", s.socTempAvg))
                            .font(.caption).monospacedDigit()
                        Text(String(format: "最低 %.1f°", s.socTempMin))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(s.overallLevel.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                // 核心四宫格：芯片 / CPU / 风扇 / 功率
                HStack(spacing: 8) {
                    MiniStat(icon: "cpu.fill", title: "芯片", value: s.socTempMax,
                             unit: "°C", digits: 1, level: s.overallLevel)
                    MiniStat(icon: "flame.fill", title: "CPU 核", value: s.cpuTempMax,
                             unit: "°C", digits: 1, level: TempLevel.of(s.cpuTempMax))
                    MiniStat(icon: "bolt.fill", title: "功率", value: s.powerWatt,
                             unit: "W", digits: 1, level: .normal)
                    MiniStat(icon: "fan.fill", title: "风扇", value: max(s.fan0RPM, s.fan1RPM),
                             unit: "RPM", digits: 0, level: s.fan0.level)
                }

                Divider()

                // 风扇：档位 + 百分比 + 仪表条
                Text("风扇转速").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FanRow(name: "风扇 0", fan: s.fan0)
                if s.fanCount > 1 { FanRow(name: "风扇 1", fan: s.fan1) }

                Divider()

                // 温度点列表：分组、彩色、带状态
                HStack {
                    Text("温度检测点").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(s.tempPoints.count) 项 · SMC + HID")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if s.tempPoints.isEmpty {
                    Text("暂无可用温度点").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(s.groupedTemps.prefix(5), id: \.group) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.group).font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            ForEach(group.points.prefix(4)) { p in
                                HStack(spacing: 5) {
                                    Circle().fill(TempLevel.of(p.celsius).color).frame(width: 5, height: 5)
                                    Text(p.label).font(.caption).lineLimit(1)
                                    Text(p.source).font(.caption2).foregroundStyle(.quaternary)
                                    Spacer()
                                    Text(String(format: "%.1f°", p.celsius))
                                        .font(.caption.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(TempLevel.of(p.celsius).color)
                                }
                            }
                        }
                    }
                    if s.tempPoints.count > 12 {
                        Text("更多温度点见详情窗口…")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if !model.history.isEmpty {
                    Divider()
                    HStack {
                        Text("温度趋势").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f° – %.0f°",
                                    model.history.min() ?? 0, model.history.max() ?? 0))
                            .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    }
                    Sparkline(values: model.history).frame(height: 34)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("未能读取传感器数据").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Divider()
            HStack(spacing: 8) {
                Button { openDetail() } label: { Label("详情", systemImage: "rectangle.expand.vertical") }
                Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// 下拉面板里的紧凑数值卡
struct MiniStat: View {
    let icon: String
    let title: String
    let value: Double
    let unit: String
    let digits: Int
    let level: TempLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.\(digits)f", value))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit().minimumScaleFactor(0.7)
                    .foregroundStyle(level.color)
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(level.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 迷你曲线

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let minV = (values.min() ?? 0) - 2
            let maxV = (values.max() ?? 1) + 2
            let range = max(maxV - minV, 1)
            let color = TempLevel.of(values.last ?? 0).color
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * geo.size.width
                    let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 详情窗口

struct DetailView: View {
    @ObservedObject var model: SensorModel
    var body: some View {
        let s = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "thermometer.sun.fill").font(.largeTitle)
                        .foregroundStyle(s.overallLevel.color)
                    VStack(alignment: .leading) {
                        Text("MacSensors").font(.title2).bold()
                        Text("SMC + HID 双通道 · 免 sudo 原生采集")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    LevelBadge(level: s.overallLevel)
                    Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                }

                HStack(spacing: 12) {
                    BigStat(title: "芯片最高", value: s.socTempMax, unit: "°C", level: s.overallLevel)
                    BigStat(title: "CPU 核心", value: s.cpuTempMax, unit: "°C", level: TempLevel.of(s.cpuTempMax))
                    BigStat(title: "片上平均", value: s.socTempAvg, unit: "°C", level: TempLevel.of(s.socTempAvg))
                    BigStat(title: "片上最低", value: s.socTempMin, unit: "°C", level: TempLevel.of(s.socTempMin))
                }

                // 风扇区：改成仪表化的可视行
                VStack(alignment: .leading, spacing: 10) {
                    Text("风扇").font(.headline)
                    FanRow(name: "风扇 0", fan: s.fan0)
                    if s.fanCount > 1 { FanRow(name: "风扇 1", fan: s.fan1) }
                }
                .padding(12)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

                if !model.history.isEmpty {
                    VStack(alignment: .leading) {
                        Text("温度趋势（最近 \(model.history.count) 次）")
                            .font(.caption).foregroundStyle(.secondary)
                        Sparkline(values: model.history).frame(height: 70)
                            .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // 所有温度点，按分组展开
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("温度检测点").font(.headline)
                        Spacer()
                        Text("\(s.tempPoints.count) 项")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(s.groupedTemps, id: \.group) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.group).font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.points) { p in
                                HStack(spacing: 6) {
                                    Circle().fill(TempLevel.of(p.celsius).color)
                                        .frame(width: 6, height: 6)
                                    Text(p.label).font(.callout)
                                    Text(p.key).font(.caption2).foregroundStyle(.quaternary)
                                    Spacer()
                                    Text(String(format: "%.1f °C", p.celsius))
                                        .font(.callout.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(TempLevel.of(p.celsius).color)
                                    Text(TempLevel.of(p.celsius).title)
                                        .font(.caption2)
                                        .foregroundStyle(TempLevel.of(p.celsius).color)
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("系统信息").font(.headline); Text("") }
                    Divider()
                    GridRow { Text("系统功率"); Text(String(format: "%.1f W", s.powerWatt)).monospacedDigit() }
                    GridRow { Text("电池温度"); Text(String(format: "%.1f °C", s.batteryTemp)).monospacedDigit() }
                    GridRow { Text("SMC key 数"); Text("\(s.smcKeyCount)").monospacedDigit() }
                    GridRow { Text("HID 测温点"); Text("\(s.hidSensorCount)").monospacedDigit() }
                    GridRow { Text("风扇数"); Text("\(s.fanCount)").monospacedDigit() }
                }
                .font(.callout)

                Spacer(minLength: 0)
                Text("数据每 5 秒刷新 · 颜色随温度/负载变化：青=凉爽 绿=正常 黄=偏热 橙=较热 红=高温")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .frame(minWidth: 480, minHeight: 600)
    }
}

struct BigStat: View {
    let title: String
    let value: Double
    let unit: String
    let level: TempLevel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.7)
                    .foregroundStyle(level.color)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Image(systemName: level.symbol).font(.caption2)
                Text(level.title).font(.caption2)
            }
            .foregroundStyle(level.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(level.color.opacity(0.3), lineWidth: 1))
    }
}
