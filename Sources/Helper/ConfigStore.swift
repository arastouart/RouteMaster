import Foundation

/// The daemon owns `config.json` (root-owned, 0644) as the single source of truth.
/// The app pushes an `AppConfig` via `applyConfig`; the daemon persists and re-applies.
final class ConfigStore {

    private let fm = FileManager.default
    private let lock = NSLock()
    private(set) var current: AppConfig

    init() {
        // Ensure the support + log directories exist (created as root by the daemon).
        ConfigStore.ensureDirectory(HelperConstants.supportDirectory)
        ConfigStore.ensureDirectory(HelperConstants.logDirectory)

        if let loaded = ConfigStore.loadFromDisk() {
            current = loaded
        } else {
            // First run: write the seed config (dryRun = true).
            current = AppConfig.seed
            try? ConfigStore.writeToDisk(current)
        }
    }

    /// Persist a new configuration pushed by the app.
    func save(_ config: AppConfig) throws {
        lock.lock(); defer { lock.unlock() }
        try ConfigStore.writeToDisk(config)
        current = config
    }

    func snapshot() -> AppConfig {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    // MARK: - Disk

    private static func loadFromDisk() -> AppConfig? {
        guard let data = FileManager.default.contents(atPath: HelperConstants.configPath) else {
            return nil
        }
        return try? JSONDecoder.routeMaster.decode(AppConfig.self, from: data)
    }

    private static func writeToDisk(_ config: AppConfig) throws {
        let data = try JSONEncoder.routeMaster.encode(config)
        let path = HelperConstants.configPath
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        // 0644, root-owned (the daemon runs as root).
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: path)
    }

    private static func ensureDirectory(_ path: String) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }
}
