import Foundation
import SwiftUI
import UserNotifications

/// App-side view model: owns the editable `AppConfig`, pushes changes to the daemon,
/// and polls `currentStatus` for live UI. Also relays daemon Geo-Lock callbacks to
/// `UNUserNotification`.
///
/// NOTE: uses `ObservableObject` (not the `@Observable` macro) because the deployment
/// target is macOS 13; the Observation framework requires macOS 14.
@MainActor
final class ConfigViewModel: ObservableObject {

    @Published var config: AppConfig = .seed
    @Published var status: StatusDTO?
    @Published var logLines: [String] = []
    @Published var lastError: String?
    @Published var connected: Bool = false

    /// Set true once the user has explicitly confirmed leaving dry-run at least once.
    @Published var dryRunDisableConfirmed: Bool = false

    let connection = HelperConnection()
    let installer = HelperInstaller()

    private var pollTask: Task<Void, Never>?

    init() {
        wireClientCallbacks()
    }

    // MARK: - Client callbacks (daemon -> app)

    private func wireClientCallbacks() {
        connection.client.onGeoLockChange = { [weak self] domain, state, country in
            Task { @MainActor in self?.postGeoNotification(domain: domain, state: state, country: country) }
        }
        connection.client.onLog = { [weak self] line in
            Task { @MainActor in
                guard let self else { return }
                self.logLines.append(line)
                if self.logLines.count > 500 { self.logLines.removeFirst(self.logLines.count - 500) }
            }
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postGeoNotification(domain: String, state: GeoLockState, country: String?) {
        let content = UNMutableNotificationContent()
        switch state {
        case .violated:
            content.title = "Geo-Lock triggered"
            content.body = "\(domain) blocked — external location \(country ?? "unknown") "
                         + "does not match the required country."
        case .compliant:
            content.title = "Geo-Lock cleared"
            content.body = "\(domain) restored — location is compliant again."
        case .unknown:
            return
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: "geo-\(domain)-\(state.rawValue)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Lifecycle

    func onAppear() {
        requestNotificationAuthorization()
        installer.refreshState()
        Task { await loadConfig() }
        startPolling()
    }

    func installHelper() {
        installer.register()
        if installer.state != .enabled {
            installer.openLoginItemsSettings()
        }
        Task { await loadConfig() }
    }

    func uninstallHelper() {
        installer.unregister()
    }

    // MARK: - Config load/save

    func loadConfig() async {
        do {
            config = try await connection.getConfig()
            connected = true
            lastError = nil
        } catch {
            connected = false
            // Keep the local seed/default so the UI still renders when the daemon is absent.
            lastError = "Daemon not reachable yet: \(error)"
        }
    }

    /// Push the current edited config to the daemon (source of truth).
    func saveConfig() async {
        do {
            try await connection.applyConfig(config)
            connected = true
            lastError = nil
        } catch {
            connected = false
            lastError = "applyConfig failed: \(error)"
        }
    }

    // MARK: - Engine control

    func startEngine() async {
        do { try await connection.startEngine(); lastError = nil }
        catch { lastError = "startEngine failed: \(error)" }
    }

    func stopEngine() async {
        do { try await connection.stopEngine(); lastError = nil }
        catch { lastError = "stopEngine failed: \(error)" }
    }

    func reresolveNow() async {
        do { try await connection.reresolveNow(); lastError = nil }
        catch { lastError = "reresolve failed: \(error)" }
    }

    func dryRunPreview() async -> [String] {
        (try? await connection.dryRunPreview()) ?? ["<preview unavailable — daemon not reachable>"]
    }

    // MARK: - Editing helpers (each mutation persists to the daemon)

    func setDryRun(_ value: Bool) {
        config.dryRun = value
        Task { await saveConfig() }
    }

    func addSplitDomain(_ domain: String) {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !d.isEmpty, !config.splitDomains.contains(where: { $0.domain == d }) else { return }
        config.splitDomains.append(RoutedDomain(domain: d))
        Task { await saveConfig() }
    }

    func removeSplitDomains(at offsets: IndexSet) {
        config.splitDomains.remove(atOffsets: offsets)
        Task { await saveConfig() }
    }

    func addGeoRule(domain: String, country: String) {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !d.isEmpty, c.count == 2,
              !config.geoLockRules.contains(where: { $0.domain == d }) else { return }
        config.geoLockRules.append(GeoLockRule(domain: d, requiredCountry: c))
        Task { await saveConfig() }
    }

    func removeGeoRules(at offsets: IndexSet) {
        config.geoLockRules.remove(atOffsets: offsets)
        Task { await saveConfig() }
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    private func refreshStatus() async {
        do {
            let s = try await connection.currentStatus()
            status = s
            connected = true
        } catch {
            connected = false
        }
    }

    var engineRunning: Bool { status?.engineRunning ?? false }
}
