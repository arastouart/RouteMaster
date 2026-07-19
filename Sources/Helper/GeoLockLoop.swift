import Foundation

/// Location-aware kill-switch.
///
/// Every `geoCheckIntervalSeconds` it determines the external egress country over the
/// DEFAULT route (which reflects the VPN exit — the intended vantage point for geo).
/// For each rule, a mismatch (or a missing VPN default) is a VIOLATION: the rule's
/// resolved IPs are blackholed to `127.0.0.1`. When compliant again, blackholes lift.
///
/// State toggles are debounced: a rule must see `geoDebounceCount` consecutive checks
/// in the new state before it flips, to avoid flapping.
///
/// SAFETY: blackholing goes through `RouteManager`/`ShellRunner`, so it is suppressed
/// under dry-run exactly like split routes.
final class GeoLockLoop {

    private let shell: ShellRunner
    private let configStore: ConfigStore
    private let inspector: NetworkInspector
    private let routeManager: RouteManager

    private let queue = DispatchQueue(label: "com.routemaster.helper.geolock")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    // Per-domain committed state + debounce counters (pure state machine).
    private var debouncer = GeoDebouncer(threshold: 3)
    /// Domain -> resolved IPs (for the rule) most recently seen, used for blackholing.
    private var ruleIPs: [String: [String]] = [:]

    // Last external observation.
    private var externalCountry: String?
    private var externalIP: String?
    private var lastCheck: Date?

    /// Invoked when a rule's committed state changes (app posts a notification).
    var onStateChange: ((_ domain: String, _ state: GeoLockState, _ country: String?) -> Void)?

    init(shell: ShellRunner, configStore: ConfigStore,
         inspector: NetworkInspector, routeManager: RouteManager) {
        self.shell = shell
        self.configStore = configStore
        self.inspector = inspector
        self.routeManager = routeManager
    }

    // MARK: - Lifecycle

    func start() {
        let config = configStore.snapshot()
        lock.lock()
        debouncer = GeoDebouncer(threshold: config.geoDebounceCount)
        lock.unlock()
        let interval = max(5, config.geoCheckIntervalSeconds)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func stop(liftBlackholes: Bool) {
        timer?.cancel()
        timer = nil
        if liftBlackholes && !shell.dryRun {
            routeManager.removeAllBlackholes()
        }
    }

    // MARK: - Status accessors

    func statuses() -> [GeoLockStatusDTO] {
        let config = configStore.snapshot()
        lock.lock()
        let committed = debouncer.committed
        let ips = ruleIPs
        lock.unlock()
        let black = Set(routeManager.blackholedIPs)

        return config.geoLockRules.map { rule in
            let ruleResolved = ips[rule.domain] ?? []
            return GeoLockStatusDTO(
                domain: rule.domain,
                requiredCountry: rule.requiredCountry,
                state: committed[rule.domain] ?? .unknown,
                blackholedIPs: ruleResolved.filter { black.contains($0) }
            )
        }
    }

    func external() -> (country: String?, ip: String?, date: Date?) {
        lock.lock(); defer { lock.unlock() }
        return (externalCountry, externalIP, lastCheck)
    }

    /// IPs that should currently be blackholed (for dry-run preview): the resolved IPs
    /// of every rule whose committed state is `.violated`.
    func desiredBlackholeIPs() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        var set = Set<String>()
        for (domain, state) in debouncer.committed where state == .violated {
            set.formUnion(ruleIPs[domain] ?? [])
        }
        return set
    }

    // MARK: - Core check

    private func tick() {
        let config = configStore.snapshot()
        guard !config.geoLockRules.isEmpty else { return }

        // 1) External country over the DEFAULT route (VPN vantage point).
        let net = inspector.inspect()
        let geo = fetchExternalGeo()
        lock.lock()
        externalCountry = geo?.country
        externalIP = geo?.ip
        lastCheck = Date()
        lock.unlock()

        // 2) Resolve each rule's IPs so we know what to blackhole. We resolve over the
        //    physical interface (same vantage as split routing) so the IP set matches
        //    what the user would otherwise reach.
        let resolver: DNSResolver? = {
            guard let ip = net.physicalSourceIP, let iface = net.physicalInterface else { return nil }
            return DNSResolver(sourceIP: ip, interfaceName: iface)
        }()

        // 3) Evaluate each rule.
        var desiredBlackhole = Set<String>()
        for rule in config.geoLockRules where rule.enabled {
            if let resolver {
                let ips = resolver.resolveA(rule.domain).map(\.ip)
                if !ips.isEmpty {
                    lock.lock(); ruleIPs[rule.domain] = ips; lock.unlock()
                }
            }

            let compliant = evaluateCompliance(rule: rule, net: net, country: geo?.country)
            let target: GeoLockState = compliant ? .compliant : .violated

            lock.lock()
            let result = debouncer.observe(domain: rule.domain, target: target)
            if result.state == .violated {
                desiredBlackhole.formUnion(ruleIPs[rule.domain] ?? [])
            }
            lock.unlock()

            if result.changed {
                onStateChange?(rule.domain, result.state, geo?.country)
            }
        }

        // 4) Apply blackholes (suppressed under dry-run by ShellRunner).
        routeManager.reconcileBlackholes(desiredIPs: desiredBlackhole)
    }

    // MARK: - External geo lookup (over the default route = VPN vantage point)

    private struct GeoResult { let country: String; let ip: String? }

    /// Query the external IP + country. Primary: ip-api.com, fallback: ipinfo.io.
    /// Uses the system default route on purpose (that is the VPN exit). Timeout + one
    /// backoff retry per endpoint.
    private func fetchExternalGeo() -> GeoResult? {
        if let r = fetchGeo(from: "http://ip-api.com/json/", countryKey: "countryCode",
                            ipKey: "query") { return r }
        // Backoff before trying the fallback.
        Thread.sleep(forTimeInterval: 0.5)
        return fetchGeo(from: "https://ipinfo.io/json", countryKey: "country", ipKey: "ip")
    }

    private func fetchGeo(from urlString: String, countryKey: String, ipKey: String) -> GeoResult? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("RouteMaster/0.1", forHTTPHeaderField: "User-Agent")

        var out: GeoResult?
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            guard let country = obj[countryKey] as? String, !country.isEmpty else { return }
            out = GeoResult(country: country.uppercased(), ip: obj[ipKey] as? String)
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 8)
        return out
    }

    /// A rule is compliant only when the VPN default is up AND the external country
    /// matches the required country.
    private func evaluateCompliance(rule: GeoLockRule, net: NetworkStateDTO,
                                    country: String?) -> Bool {
        guard net.vpnActive else { return false }          // VPN down/absent => violation
        guard let country else { return false }            // unknown country => be safe, violate
        return country.uppercased() == rule.requiredCountry.uppercased()
    }
}
