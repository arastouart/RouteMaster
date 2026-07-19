import Foundation

// MARK: - Configuration model (single source of truth, owned by the daemon)

/// A domain the user wants split-routed out the physical interface (bypassing the VPN).
public struct RoutedDomain: Codable, Hashable, Identifiable, Sendable {
    public var id: String { domain }
    public var domain: String
    /// User can pause a single domain without deleting it.
    public var enabled: Bool

    public init(domain: String, enabled: Bool = true) {
        self.domain = domain
        self.enabled = enabled
    }
}

/// A Geo-Lock rule: a domain that is only permitted to resolve/route when the VPN's
/// external egress is in `requiredCountry` (ISO 3166-1 alpha-2, e.g. "TR").
public struct GeoLockRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String { domain }
    public var domain: String
    /// ISO alpha-2 country code required for this domain to be reachable.
    public var requiredCountry: String
    public var enabled: Bool

    public init(domain: String, requiredCountry: String, enabled: Bool = true) {
        self.domain = domain
        self.requiredCountry = requiredCountry.uppercased()
        self.enabled = enabled
    }
}

/// The full application configuration. Serialized to `config.json` by the daemon and
/// pushed from the app via `applyConfig`.
public struct AppConfig: Codable, Hashable, Sendable {
    public var splitDomains: [RoutedDomain]
    public var geoLockRules: [GeoLockRule]

    /// How often split domains are re-resolved + routes reconciled.
    public var resolveIntervalSeconds: Int
    /// How often the Geo-Lock loop checks external country.
    public var geoCheckIntervalSeconds: Int

    /// SAFETY: when true (the default, especially on first run) NO live routing-table
    /// mutation happens — commands are only recorded and surfaced via dry-run preview.
    public var dryRun: Bool

    /// Number of consecutive geo checks required before toggling a violation state
    /// (debounce against flapping).
    public var geoDebounceCount: Int

    /// OPTIONAL geo provider selection for the Geo-Lock external-country lookup.
    /// Values: `"ip-api"`, `"ipinfo"`. `nil`/empty => the default fallback chain
    /// (ip-api.com then ipinfo.io, no key) — identical to legacy behavior.
    /// Optional so existing `config.json` files without this key still decode cleanly
    /// (synthesized `Codable` uses `decodeIfPresent` -> nil for absent optionals).
    public var geoProvider: String?

    /// OPTIONAL API key for the selected paid geo provider. `nil`/empty => no key
    /// (free endpoints). Stored locally in config.json only; never seeded, never committed.
    public var geoAPIKey: String?

    public init(
        splitDomains: [RoutedDomain],
        geoLockRules: [GeoLockRule],
        resolveIntervalSeconds: Int = 300,
        geoCheckIntervalSeconds: Int = 30,
        dryRun: Bool = true,
        geoDebounceCount: Int = 3,
        geoProvider: String? = nil,
        geoAPIKey: String? = nil
    ) {
        self.splitDomains = splitDomains
        self.geoLockRules = geoLockRules
        self.resolveIntervalSeconds = resolveIntervalSeconds
        self.geoCheckIntervalSeconds = geoCheckIntervalSeconds
        self.dryRun = dryRun
        self.geoDebounceCount = geoDebounceCount
        self.geoProvider = geoProvider
        self.geoAPIKey = geoAPIKey
    }

    /// Seed configuration written on first launch.
    /// SAFETY: `dryRun` defaults to true.
    public static let seed = AppConfig(
        splitDomains: [RoutedDomain(domain: "bitgraph.ir")],
        geoLockRules: [GeoLockRule(domain: "claude.ai", requiredCountry: "TR")],
        dryRun: true
    )
}

// MARK: - Runtime state DTOs (daemon -> app, read-only snapshots)

/// A point-in-time snapshot of the host's network vantage points.
public struct NetworkStateDTO: Codable, Hashable, Sendable {
    /// Default route gateway IP (whatever currently owns the default route).
    public var defaultGateway: String?
    /// Interface the default route egresses (e.g. `utun4` when a VPN is up, else `en0`).
    public var defaultInterface: String?
    /// The physical, en0-like interface used for split routing / interface-bound DNS.
    public var physicalInterface: String?
    /// The physical interface's gateway (used for `route add -host <ip> <gw>`).
    public var physicalGateway: String?
    /// The physical interface's source IPv4 (used to bind DNS sockets).
    public var physicalSourceIP: String?
    /// True when the default route egresses a utun*/ppp* interface (VPN considered up).
    public var vpnActive: Bool

    public init(
        defaultGateway: String? = nil,
        defaultInterface: String? = nil,
        physicalInterface: String? = nil,
        physicalGateway: String? = nil,
        physicalSourceIP: String? = nil,
        vpnActive: Bool = false
    ) {
        self.defaultGateway = defaultGateway
        self.defaultInterface = defaultInterface
        self.physicalInterface = physicalInterface
        self.physicalGateway = physicalGateway
        self.physicalSourceIP = physicalSourceIP
        self.vpnActive = vpnActive
    }
}

/// Per-domain resolution + routing snapshot.
public struct DomainStatusDTO: Codable, Hashable, Sendable {
    public var domain: String
    public var resolvedIPs: [String]
    /// IPs for which a host route is currently installed (or would be, in dry-run).
    public var activeRouteIPs: [String]
    public var lastResolved: Date?

    public init(domain: String, resolvedIPs: [String], activeRouteIPs: [String], lastResolved: Date?) {
        self.domain = domain
        self.resolvedIPs = resolvedIPs
        self.activeRouteIPs = activeRouteIPs
        self.lastResolved = lastResolved
    }
}

/// Geo-Lock compliance snapshot.
public enum GeoLockState: String, Codable, Sendable {
    case unknown
    case compliant
    case violated
}

public struct GeoLockStatusDTO: Codable, Hashable, Sendable {
    public var domain: String
    public var requiredCountry: String
    public var state: GeoLockState
    /// IPs currently blackholed for this domain (or that would be, in dry-run).
    public var blackholedIPs: [String]

    public init(domain: String, requiredCountry: String, state: GeoLockState, blackholedIPs: [String]) {
        self.domain = domain
        self.requiredCountry = requiredCountry
        self.state = state
        self.blackholedIPs = blackholedIPs
    }
}

/// The aggregate status the app polls to render live UI.
public struct StatusDTO: Codable, Hashable, Sendable {
    public var engineRunning: Bool
    public var dryRun: Bool
    public var network: NetworkStateDTO
    public var domains: [DomainStatusDTO]
    public var geoLocks: [GeoLockStatusDTO]
    /// External country as last observed over the default route (VPN vantage point).
    public var externalCountry: String?
    public var externalIP: String?
    public var lastGeoCheck: Date?
    /// Rolling tail of ShellRunner command log lines (most recent last).
    public var recentCommands: [String]

    public init(
        engineRunning: Bool,
        dryRun: Bool,
        network: NetworkStateDTO,
        domains: [DomainStatusDTO],
        geoLocks: [GeoLockStatusDTO],
        externalCountry: String? = nil,
        externalIP: String? = nil,
        lastGeoCheck: Date? = nil,
        recentCommands: [String] = []
    ) {
        self.engineRunning = engineRunning
        self.dryRun = dryRun
        self.network = network
        self.domains = domains
        self.geoLocks = geoLocks
        self.externalCountry = externalCountry
        self.externalIP = externalIP
        self.lastGeoCheck = lastGeoCheck
        self.recentCommands = recentCommands
    }
}

// MARK: - JSON helpers

public extension JSONEncoder {
    static var routeMaster: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

public extension JSONDecoder {
    static var routeMaster: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
