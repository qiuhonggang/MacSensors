import SwiftUI
import AppKit
import WidgetKit

// MARK: - 定时采样模型

@MainActor
final class SensorModel: ObservableObject {
    @Published var snapshot: SensorSnapshot = .empty
    @Published var history: [Double] = []       // socTempMax 历史（用于菜单栏迷你曲线）
    private var timer: Timer?

    init() {
        refresh()
        // 每 5 秒采样一次
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // 采集在后台线程做，避免阻塞菜单栏 UI
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

    /// 打开并前置详情窗口。
    /// LSUIElement(.accessory) 应用开的窗口不会自动抢焦点，常被其它 App 的窗口挡住，
    /// 所以需要显式激活 + orderFrontRegardless 才能真正显示出来。
    private func openDetail() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "detail")
        // openWindow 是异步创建窗口，稍等后再把窗口拉到最前
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for window in NSApp.windows where window.title == "MacSensors 详情" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        // 菜单栏常驻项
        MenuBarExtra {
            MenuContentView(model: model, openDetail: openDetail)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                Text(model.menuTitle)
            }
        }
        .menuBarExtraStyle(.menu)

        // 详情窗口（可选打开）
        Window("MacSensors 详情", id: "detail") {
            DetailView(model: model)
        }
        .defaultSize(width: 460, height: 520)
    }
}

// MARK: - 菜单栏下拉内容

struct MenuContentView: View {
    @ObservedObject var model: SensorModel
    let openDetail: () -> Void

    var body: some View {
        let s = model.snapshot
        Group {
            if s.available {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Silicon · 实时监测").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Label("芯片最高", systemImage: "cpu.fill")
                        Spacer()
                        Text(String(format: "%.1f °C", s.socTempMax)).monospacedDigit().bold()
                    }
                    HStack {
                        Label("CPU 核心", systemImage: "flame")
                        Spacer()
                        Text(String(format: "%.1f °C", s.cpuTempMax)).monospacedDigit()
                    }
                    HStack {
                        Label("风扇 0 / 1", systemImage: "fan.fill")
                        Spacer()
                        Text(String(format: "%.0f / %.0f RPM", s.fan0RPM, s.fan1RPM)).monospacedDigit()
                    }
                    HStack {
                        Label("系统功率", systemImage: "bolt.fill")
                        Spacer()
                        Text(String(format: "%.1f W", s.powerWatt)).monospacedDigit()
                    }
                    if !model.history.isEmpty {
                        Divider()
                        Sparkline(values: model.history)
                            .frame(height: 30)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("未能读取传感器数据").foregroundStyle(.secondary)
            }
            Divider()
            Button("打开详情窗口") { openDetail() }
            Button("刷新桌面组件") { WidgetCenter.shared.reloadAllTimelines() }
            Divider()
            Button("退出 MacSensors") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .frame(minWidth: 240)
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
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * geo.size.width
                    let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 详情窗口

struct DetailView: View {
    @ObservedObject var model: SensorModel
    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "thermometer.sun.fill").font(.largeTitle).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("MacSensors").font(.title2).bold()
                    Text("SMC + HID 双通道 · 免 sudo 原生采集").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            }

            HStack(spacing: 12) {
                BigStat(title: "芯片最高", value: s.socTempMax, unit: "°C", color: .orange)
                BigStat(title: "CPU 核心", value: s.cpuTempMax, unit: "°C", color: .red)
                BigStat(title: "平均", value: s.socTempAvg, unit: "°C", color: .yellow)
            }

            if !model.history.isEmpty {
                VStack(alignment: .leading) {
                    Text("温度趋势（最近 \(model.history.count) 次）").font(.caption).foregroundStyle(.secondary)
                    Sparkline(values: model.history).frame(height: 60)
                        .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow { Text("风扇").font(.headline); Text("转速 / 目标").font(.headline) }
                Divider()
                GridRow { Text("风扇 0"); Text(String(format: "%.0f / %.0f RPM", s.fan0RPM, s.fan0Target)).monospacedDigit() }
                GridRow { Text("风扇 1"); Text(String(format: "%.0f / %.0f RPM", s.fan1RPM, s.fan1Target)).monospacedDigit() }
                Divider()
                GridRow { Text("SMC key 数"); Text("\(s.smcKeyCount)").monospacedDigit() }
                GridRow { Text("HID 测温点"); Text("\(s.hidSensorCount)").monospacedDigit() }
                GridRow { Text("电池温度"); Text(String(format: "%.1f °C", s.batteryTemp)).monospacedDigit() }
                GridRow { Text("系统功率"); Text(String(format: "%.1f W", s.powerWatt)).monospacedDigit() }
            }
            .font(.callout)

            Spacer()
            Text("数据每 5 秒刷新 · 点击菜单栏图标查看快捷信息")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(minWidth: 420, minHeight: 480)
    }
}

struct BigStat: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3), lineWidth: 1))
    }
}
