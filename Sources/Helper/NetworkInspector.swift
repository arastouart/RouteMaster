import Foundation

/// Detects the host's routing vantage points:
///   * the current default route (gateway + interface) and whether it egresses a VPN
///     tunnel (utun*/ppp*/ipsec*),
///   * the physical "en0-like" interface used for split routing even while a VPN owns
///     the default route,
///   * that physical interface's gateway (via interface-scoped route lookup) and its
///     source IPv4 (needed to bind DNS sockets and validate routes).
///
/// All parsing is done by pure static functions so they can be unit-tested against
/// captured command output without touching the network.
struct NetworkInspector {

    let shell: ShellRunner

    init(shell: ShellRunner) {
        self.shell = shell
    }

    // MARK: - Pure parsing (unit-testable)

    struct RouteGetResult: Equatable {
        var gateway: String?
        var interface: String?
    }

    /// Parse `route -n get default` / `route -n get <ip>` output.
    ///
    /// Sample:
    /// ```
    ///    route to: default
    /// destination: default
    ///     gateway: 192.168.1.1
    ///   interface: en0
    ///       flags: <UP,GATEWAY,DONE,STATIC>
    /// ```
    static func parseRouteGet(_ output: String) -> RouteGetResult {
        var result = RouteGetResult()
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "gateway":   result.gateway = value.isEmpty ? nil : value
            case "interface": result.interface = value.isEmpty ? nil : value
            default:          break
            }
        }
        return result
    }

    /// True for interfaces that represent a VPN/tunnel egress.
    static func isTunnelInterface(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.hasPrefix("utun")
            || name.hasPrefix("ppp")
            || name.hasPrefix("ipsec")
            || name.hasPrefix("tun")
            || name.hasPrefix("tap")
    }

    /// Candidate physical interfaces (Wi-Fi/Ethernet), in preference order, from
    /// `ifconfig -l` output.
    static func physicalCandidates(fromIfconfigList output: String) -> [String] {
        output
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .map(String.init)
            .filter { $0.hasPrefix("en") || $0.hasPrefix("eth") }
    }

    /// Extract the first non-`127.0.0.1` IPv4 `inet` address from `ifconfig <iface>`.
    ///
    /// Sample line: `\tinet 192.168.1.23 netmask 0xffffff00 broadcast 192.168.1.255`
    static func parseInetAddress(fromIfconfig output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let parts = rawLine.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard let idx = parts.firstIndex(of: "inet"), idx + 1 < parts.count else { continue }
            let addr = parts[idx + 1]
            if addr != "127.0.0.1" { return addr }
        }
        return nil
    }

    /// True if `ifconfig <iface>` output indicates the interface is active/running.
    static func isInterfaceActive(fromIfconfig output: String) -> Bool {
        // Prefer the explicit `status: active` line (Wi-Fi/Ethernet). Fall back to the
        // RUNNING flag in the header.
        if output.contains("status: active") { return true }
        if output.contains("status: inactive") { return false }
        if let firstLine = output.split(whereSeparator: \.isNewline).first {
            return firstLine.contains("RUNNING")
        }
        return false
    }

    // MARK: - Live inspection

    /// Build a full `NetworkStateDTO` from live command output.
    func inspect() -> NetworkStateDTO {
        // 1) Current default route.
        let def = Self.parseRouteGet(shell.routeGetDefault().stdout)
        let vpnActive = Self.isTunnelInterface(def.interface)

        // 2) Physical interface: if the default is already a physical iface, use it;
        //    otherwise pick the first active en*/eth* with an IPv4.
        let physicalIface: String?
        if let iface = def.interface, !Self.isTunnelInterface(iface) {
            physicalIface = iface
        } else {
            physicalIface = firstActivePhysicalInterface()
        }

        // 3) Physical gateway + source IP.
        var physicalGateway: String? = nil
        var physicalSourceIP: String? = nil
        if let phys = physicalIface {
            if phys == def.interface, !vpnActive {
                physicalGateway = def.gateway
            } else {
                // Interface-scoped lookup works even while the VPN owns the default.
                physicalGateway = Self.parseRouteGet(
                    shell.routeGetDefaultScoped(iface: phys).stdout
                ).gateway ?? def.gateway
            }
            physicalSourceIP = Self.parseInetAddress(fromIfconfig: shell.ifconfig(phys).stdout)
        }

        return NetworkStateDTO(
            defaultGateway: def.gateway,
            defaultInterface: def.interface,
            physicalInterface: physicalIface,
            physicalGateway: physicalGateway,
            physicalSourceIP: physicalSourceIP,
            vpnActive: vpnActive
        )
    }

    /// First active en*/eth* interface that carries a non-loopback IPv4.
    private func firstActivePhysicalInterface() -> String? {
        let candidates = Self.physicalCandidates(fromIfconfigList: shell.ifconfigList().stdout)
        for iface in candidates {
            let out = shell.ifconfig(iface).stdout
            guard Self.isInterfaceActive(fromIfconfig: out) else { continue }
            if Self.parseInetAddress(fromIfconfig: out) != nil { return iface }
        }
        return nil
    }

    /// Look up the interface index for `IP_BOUND_IF` socket binding.
    static func interfaceIndex(for name: String) -> UInt32 {
        if_nametoindex(name)
    }
}
