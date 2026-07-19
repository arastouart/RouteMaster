import Foundation

/// The object exported over XPC. Implements `RoutingProtocol` by delegating to the
/// engine, route manager, config store, and (wired in Phase 4) the Geo-Lock loop.
final class RoutingService: NSObject, RoutingProtocol {

    let shell: ShellRunner
    let configStore: ConfigStore
    let inspector: NetworkInspector
    let routeManager: RouteManager
    let engine: EngineLoop

    /// Geo-Lock hooks. Default to inert values so this file compiles/works on its own;
    /// Phase 4 assigns real closures backed by `GeoLockLoop`.
    var geoStatuses: () -> [GeoLockStatusDTO] = { [] }
    var geoExternal: () -> (country: String?, ip: String?, date: Date?) = { (nil, nil, nil) }
    var desiredBlackholeIPs: () -> Set<String> = { [] }
    /// Called by startEngine/stopEngine so the Geo-Lock loop starts/stops in lockstep.
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    /// Proxy to the connected app for daemon->app callbacks (notifications, logs).
    var clientProxy: RoutingClientProtocol?

    init(shell: ShellRunner, configStore: ConfigStore, inspector: NetworkInspector,
         routeManager: RouteManager, engine: EngineLoop) {
        self.shell = shell
        self.configStore = configStore
        self.inspector = inspector
        self.routeManager = routeManager
        self.engine = engine
        super.init()

        // Forward ShellRunner log lines to the connected app.
        shell.onLog = { [weak self] line in
            self?.clientProxy?.engineDidLog(line)
        }
    }

    // MARK: - RoutingProtocol

    func getNetworkState(withReply reply: @escaping (Data?) -> Void) {
        let net = engine.refreshNetwork()
        reply(try? JSONEncoder.routeMaster.encode(net))
    }

    func applyConfig(_ data: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            let config = try JSONDecoder.routeMaster.decode(AppConfig.self, from: data)
            try configStore.save(config)
            shell.setDryRun(config.dryRun)
            reply(true, nil)
        } catch {
            reply(false, "applyConfig failed: \(error)")
        }
    }

    func startEngine(withReply reply: @escaping (Bool, String?) -> Void) {
        // Ensure the runner reflects the persisted dry-run flag before any mutation.
        shell.setDryRun(configStore.snapshot().dryRun)
        engine.start()
        onStart()
        clientProxy?.engineDidLog("[engine] started (dryRun=\(shell.dryRun))")
        reply(true, nil)
    }

    func stopEngine(withReply reply: @escaping (Bool, String?) -> Void) {
        engine.stop(tearDownRoutes: true)
        onStop()
        clientProxy?.engineDidLog("[engine] stopped")
        reply(true, nil)
    }

    func currentStatus(withReply reply: @escaping (Data?) -> Void) {
        let ext = geoExternal()
        let status = StatusDTO(
            engineRunning: engine.running,
            dryRun: shell.dryRun,
            network: engine.currentNetwork(),
            domains: engine.domainStatuses(),
            geoLocks: geoStatuses(),
            externalCountry: ext.country,
            externalIP: ext.ip,
            lastGeoCheck: ext.date,
            recentCommands: shell.recentCommands()
        )
        reply(try? JSONEncoder.routeMaster.encode(status))
    }

    func runDryRunPreview(withReply reply: @escaping ([String]) -> Void) {
        let net = engine.currentNetwork()
        let lines = routeManager.previewCommands(
            desiredSplitIPs: engine.desiredSplitIPs(),
            gateway: net.physicalGateway,
            desiredBlackholeIPs: desiredBlackholeIPs()
        )
        reply(lines)
    }

    func reresolveNow(withReply reply: @escaping (Bool, String?) -> Void) {
        engine.tickNow()
        reply(true, nil)
    }
}
