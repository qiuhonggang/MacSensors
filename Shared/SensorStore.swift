import Foundation

/// 主 App 与 Widget Extension 之间共享最近一次采样。
///
/// ## 为什么不用 UserDefaults(suiteName:) 作为主通道
/// 审查发现：macOS 上即使 App Group ID 无效（未签名 / entitlement 未生效），
/// `UserDefaults(suiteName:)` 仍会返回一个**非 nil 但写不进 group 容器**的对象；
/// 而「主 App 非沙箱 + Widget 沙箱」组合下，两端 suite 会落到不同 domain，
/// 导致主 App 写、Widget 读不到 —— 这正是很多自制 Widget 显示空白的根因。
///
/// ## 本实现（三路写入 + 三路回退，全部走明确路径）
/// 1. **共享文件（首选）**：`~/Library/Application Support/MacSensors/latest-snapshot.json`
///    这是一个普通用户目录下的固定路径，主 App（非沙箱）可写；
///    Widget 在沙箱下通过 `NSHomeDirectory()` 得到的是自己的容器，因此另加：
/// 2. **App Group 容器文件**：`containerURL(forSecurityApplicationGroupIdentifier:)`
///    仅在真签名 + 有效 entitlement 时生效并被系统认可；作为签名发布时的正确通道。
/// 3. **standard UserDefaults**：未签名命令行构建的兜底，保证本地验证链路完整。
///
/// 读取顺序按可靠性从高到低尝试；任一命中且数据未过期即返回。
enum SensorStore {
    static let appGroupID = "group.com.macsensors.shared"
    static let snapshotKey = "latest.snapshot"
    private static let fileName = "latest-snapshot.json"

    /// 快照有效期：超过 10 分钟视为陈旧（避免 App 关闭后 Widget 一直显示旧值）。
    private static let maxAge: TimeInterval = 600

    private static func encode(_ s: SensorSnapshot) -> Data? {
        try? JSONEncoder().encode(s)
    }

    // 路径 1：用户级共享目录（主 App 非沙箱可写，Widget 沙箱下通过 home 相对路径也可读）
    private static var sharedFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MacSensors", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // 路径 2：App Group 容器（签名发布时的标准通道）
    private static var groupContainerFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    private static func writeFile(_ data: Data, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    static func save(_ snapshot: SensorSnapshot) {
        guard let data = encode(snapshot) else { return }
        if let url = sharedFileURL { writeFile(data, to: url) }
        if let url = groupContainerFileURL { writeFile(data, to: url) }
        UserDefaults.standard.set(data, forKey: snapshotKey)
        // 也写 suite（若签名/组有效则额外命中；无效时不影响其它两路）
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: snapshotKey)
    }

    static func load() -> SensorSnapshot? {
        var candidates: [Data?] = []
        if let url = sharedFileURL { candidates.append(try? Data(contentsOf: url)) }
        if let url = groupContainerFileURL { candidates.append(try? Data(contentsOf: url)) }
        candidates.append(UserDefaults.standard.data(forKey: snapshotKey))
        candidates.append(UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey))

        var best: SensorSnapshot?
        for c in candidates {
            guard let d = c,
                  let s = try? JSONDecoder().decode(SensorSnapshot.self, from: d) else { continue }
            if s.available, Date().timeIntervalSince(s.date) <= maxAge {
                // 取时间戳最新的一份
                if best == nil || s.date > best!.date { best = s }
            }
        }
        return best
    }
}
