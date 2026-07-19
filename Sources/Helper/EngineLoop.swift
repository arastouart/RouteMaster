import Foundation

/// Periodic resolve + reconcile loop for split routing.
///
/// Every `resolveIntervalSeconds` it re-inspects the network, re-resolves every enabled
/// split domain through the interface-bound `DNSResolver`, and asks `RouteManager` to
/// reconcile host routes against the freshly-resolved IP set (handling CDN IP churn).
final class EngineLoop {

    private let shell: ShellRunner
    private let inspector: NetworkInspector
    private let routeManager: RouteManager
    private let configStore: ConfigStore

    private let queue = DispatchQueue(label: "com.routemaster.helper.engine")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    // Shared, lock-guarded state read by RoutingService for status reporting.
    private var lastNetwork = NetworkStateDTO()
    private var resolutions: [String: (ips: [String], date: Date)] = [:]
    private(set) var running = false

    init(shell: ShellRunner, inspector: NetworkInspector,
         routeManager: RouteManager, configStore: ConfigStore) {
        self.shell = shell
        self.inspector = inspector
        self.routeManager = routeManager
        self.configStore = configStore
    }

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()

        let interval = max(5, configStore.snapshot().resolveIntervalSeconds)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop(tearDownRoutes: Bool) {
        lock.lock()
        running = false
        lock.unlock()
        timer?.cancel()
        timer = nil
        // Only mutate the table on stop when explicitly out of dry-run.
        if tearDownRoutes && !shell.dryRun {
            routeManager.removeAllSplitRoutes()
        }
    }

    /// Run one resolve/reconcile pass immediately (manual "re-resolve now").
    func tickNow() {
        queue.async { [weak self] in self?.tick() }
    }

    // MARK: - Core pass

    private func tick() {
        let config = configStore.snapshot()

        // 1) Refresh network vantage points.
        let net = inspector.inspect()
        lock.lock(); lastNetwork = net; lock.unlock()

        guard let sourceIP = net.physicalSourceIP,
              let iface = net.physicalInterface else {
            shell.onLog?("[engine] no physical interface/source IP; skipping resolve pass")
            return
        }

        let resolver = DNSResolver(sourceIP: sourceIP, interfaceName: iface)

        // 2) Resolve every enabled split domain over the interface-bound socket.
        var allDesired = Set<String>()
        for domain in config.splitDomains where domain.enabled {
            let recs = resolver.resolveA(domain.domain)
            let ips = recs.map(\.ip).sorted()
            lock.lock()
            resolutions[domain.domain] = (ips: ips, date: Date())
            lock.unlock()
            allDesired.formUnion(ips)
        }

        // 3) Reconcile host routes (suppressed automatically when dry-run is on).
        if let gw = net.physicalGateway {
            routeManager.reconcileSplitRoutes(desiredIPs: allDesired, gateway: gw)
        } else {
            shell.onLog?("[engine] no physical gateway; cannot reconcile split routes")
        }
    }

    // MARK: - Status accessors

    func currentNetwork() -> NetworkStateDTO {
        lock.lock(); defer { lock.unlock() }
        return lastNetwork
    }

    /// Refresh network immediately (used by getNetworkState even when engine stopped).
    func refreshNetwork() -> NetworkStateDTO {
        let net = inspector.inspect()
        lock.lock(); lastNetwork = net; lock.unlock()
        return net
    }

    func domainStatuses() -> [DomainStatusDTO] {
        lock.lock()
        let snapshot = resolutions
        lock.unlock()
        let installed = Set(routeManager.installedSplitIPs)
        return snapshot
            .map { domain, val in
                DomainStatusDTO(
                    domain: domain,
                    resolvedIPs: val.ips,
                    activeRouteIPs: val.ips.filter { installed.contains($0) },
                    lastResolved: val.date
                )
            }
            .sorted { $0.domain < $1.domain }
    }

    /// The union of resolved IPs for enabled split domains (for dry-run preview).
    func desiredSplitIPs() -> Set<String> {
        let config = configStore.snapshot()
        lock.lock(); let snapshot = resolutions; lock.unlock()
        var set = Set<String>()
        for domain in config.splitDomains where domain.enabled {
            set.formUnion(snapshot[domain.domain]?.ips ?? [])
        }
        return set
    }
}
