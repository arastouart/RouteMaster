import Foundation

/// Installs and reconciles host routes. Two kinds of routes are tracked:
///   * split routes — `route add -host <ip> <physicalGateway>` (more specific than the
///     VPN default, so the host egresses en0),
///   * blackhole routes — `route add -host <ip> 127.0.0.1` (Geo-Lock kill-switch).
///
/// Every mutation goes through `ShellRunner`, so dry-run suppression is automatic. The
/// in-memory tracking reflects *intended* state (updated even in dry-run) so that
/// reconciliation diffs and status reporting stay consistent.
final class RouteManager {

    private let shell: ShellRunner
    private let lock = NSLock()

    /// ip -> gateway for currently-installed split host routes.
    private var splitRoutes: [String: String] = [:]
    /// Set of currently-blackholed ips.
    private var blackholed: Set<String> = []

    init(shell: ShellRunner) {
        self.shell = shell
    }

    // MARK: - Snapshot accessors

    var installedSplitIPs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(splitRoutes.keys).sorted()
    }

    var blackholedIPs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(blackholed).sorted()
    }

    // MARK: - Split routes

    /// Reconcile installed split routes against the desired set for the given gateway.
    /// Adds newly-desired IPs, removes stale ones (handles CDN IP churn each interval).
    func reconcileSplitRoutes(desiredIPs: Set<String>, gateway: String) {
        lock.lock()
        let current = Set(splitRoutes.keys)
        let toAdd = desiredIPs.subtracting(current)
        let toRemove = current.subtracting(desiredIPs)
        lock.unlock()

        for ip in toAdd.sorted() {
            let r = shell.routeAddHost(ip: ip, gateway: gateway)
            // Track as installed if it succeeded OR was suppressed by dry-run.
            if r.exitCode == 0 {
                lock.lock(); splitRoutes[ip] = gateway; lock.unlock()
            }
        }
        for ip in toRemove.sorted() {
            let r = shell.routeDeleteHost(ip: ip)
            if r.exitCode == 0 {
                lock.lock(); splitRoutes.removeValue(forKey: ip); lock.unlock()
            }
        }
    }

    /// Tear down all split routes (used on stop when not in dry-run).
    func removeAllSplitRoutes() {
        let ips = installedSplitIPs
        for ip in ips {
            let r = shell.routeDeleteHost(ip: ip)
            if r.exitCode == 0 {
                lock.lock(); splitRoutes.removeValue(forKey: ip); lock.unlock()
            }
        }
    }

    // MARK: - Blackhole routes (Geo-Lock)

    func reconcileBlackholes(desiredIPs: Set<String>) {
        lock.lock()
        let current = blackholed
        let toAdd = desiredIPs.subtracting(current)
        let toRemove = current.subtracting(desiredIPs)
        lock.unlock()

        for ip in toAdd.sorted() {
            let r = shell.routeBlackhole(ip: ip)
            if r.exitCode == 0 {
                lock.lock(); blackholed.insert(ip); lock.unlock()
            }
        }
        for ip in toRemove.sorted() {
            let r = shell.routeUnblackhole(ip: ip)
            if r.exitCode == 0 {
                lock.lock(); blackholed.remove(ip); lock.unlock()
            }
        }
    }

    func removeAllBlackholes() {
        let ips = blackholedIPs
        for ip in ips {
            let r = shell.routeUnblackhole(ip: ip)
            if r.exitCode == 0 {
                lock.lock(); blackholed.remove(ip); lock.unlock()
            }
        }
    }

    // MARK: - Dry-run preview

    /// Compute the exact commands that WOULD run to reach the desired state from the
    /// currently-tracked state, WITHOUT executing anything. Feeds `runDryRunPreview`.
    func previewCommands(
        desiredSplitIPs: Set<String>,
        gateway: String?,
        desiredBlackholeIPs: Set<String>
    ) -> [String] {
        lock.lock()
        let curSplit = Set(splitRoutes.keys)
        let curBlack = blackholed
        lock.unlock()

        var lines: [String] = []
        let gw = gateway ?? "<no-physical-gateway>"

        for ip in desiredSplitIPs.subtracting(curSplit).sorted() {
            lines.append("\(ShellRunner.routeBin) add -host \(ip) \(gw)")
        }
        for ip in curSplit.subtracting(desiredSplitIPs).sorted() {
            lines.append("\(ShellRunner.routeBin) delete -host \(ip)")
        }
        for ip in desiredBlackholeIPs.subtracting(curBlack).sorted() {
            lines.append("\(ShellRunner.routeBin) add -host \(ip) 127.0.0.1  # blackhole")
        }
        for ip in curBlack.subtracting(desiredBlackholeIPs).sorted() {
            lines.append("\(ShellRunner.routeBin) delete -host \(ip)  # restore (un-blackhole)")
        }

        if lines.isEmpty {
            lines.append("# no route changes needed — desired state matches installed state")
        }
        return lines
    }
}
