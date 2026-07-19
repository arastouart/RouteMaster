import Foundation

/// XPC contract vended by the privileged daemon and consumed by the app.
///
/// ## Why the replies are `Data`, not the DTO types directly
/// `NSXPCConnection` can only marshal Objective-C `NSSecureCoding` objects across the
/// wire. Our DTOs are Swift `Codable` value types, which are NOT `NSSecureCoding`, so
/// they cannot be sent directly. Instead each "typed" reply carries JSON `Data` that
/// the caller decodes with `JSONDecoder.routeMaster`. The app layer wraps these in
/// typed `async` helpers (see `HelperConnection`) so callers still work with DTOs.
///
/// Both peers validate each other with `setCodeSigningRequirement(_:)` (macOS 13+);
/// there is no custom auth handshake.
@objc public protocol RoutingProtocol {

    /// Current network vantage points. Reply is JSON-encoded `NetworkStateDTO` (or nil).
    func getNetworkState(withReply reply: @escaping (Data?) -> Void)

    /// The daemon's current persisted configuration. Reply is JSON-encoded `AppConfig`
    /// (or nil). The app uses this to populate its editable UI from the source of truth.
    func getConfig(withReply reply: @escaping (Data?) -> Void)

    /// Persist + apply a new configuration. `data` is a JSON-encoded `AppConfig`.
    /// Reply: (ok, errorMessage?).
    func applyConfig(_ data: Data, withReply reply: @escaping (Bool, String?) -> Void)

    /// Start the resolve/reconcile + Geo-Lock loops. Reply: (ok, errorMessage?).
    func startEngine(withReply reply: @escaping (Bool, String?) -> Void)

    /// Stop the loops (does not tear down installed routes unless dry-run false; see impl).
    /// Reply: (ok, errorMessage?).
    func stopEngine(withReply reply: @escaping (Bool, String?) -> Void)

    /// Aggregate live status. Reply is JSON-encoded `StatusDTO` (or nil).
    func currentStatus(withReply reply: @escaping (Data?) -> Void)

    /// The exact route/blackhole commands that WOULD run right now, without executing
    /// any of them. Safe to call regardless of the dry-run flag.
    func runDryRunPreview(withReply reply: @escaping ([String]) -> Void)

    /// Force an immediate re-resolve + reconcile of all split domains (manual refresh).
    /// Reply: (ok, errorMessage?).
    func reresolveNow(withReply reply: @escaping (Bool, String?) -> Void)
}

/// Callbacks the daemon invokes on the app (daemon cannot post user notifications
/// itself). Set as the connection's `exportedObject` by the app.
@objc public protocol RoutingClientProtocol {
    /// Geo-Lock state changed for `domain`. `stateRaw` is `GeoLockState.rawValue`.
    /// The app posts a `UNUserNotification` in response.
    func geoLockDidChange(domain: String, stateRaw: String, country: String?)

    /// A human-readable engine event, for the app's live log view.
    func engineDidLog(_ line: String)
}
