import Foundation

/// Manages the validated XPC connection from the app to the privileged daemon and
/// exposes typed `async` wrappers over the `Data`-based `RoutingProtocol`.
///
/// The app pins the daemon's code-signing requirement with `setCodeSigningRequirement`
/// (macOS 13+). It also exports a `RoutingClientProtocol` object so the daemon can push
/// Geo-Lock notifications and log lines back.
final class HelperConnection: NSObject {

    /// Client object the daemon calls back into (notifications, log streaming).
    final class Client: NSObject, RoutingClientProtocol {
        var onGeoLockChange: ((String, GeoLockState, String?) -> Void)?
        var onLog: ((String) -> Void)?

        func geoLockDidChange(domain: String, stateRaw: String, country: String?) {
            let state = GeoLockState(rawValue: stateRaw) ?? .unknown
            onGeoLockChange?(domain, state, country)
        }
        func engineDidLog(_ line: String) {
            onLog?(line)
        }
    }

    let client = Client()
    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "com.routemaster.app.xpc")

    // MARK: - Connection lifecycle

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: RoutingProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: RoutingClientProtocol.self)
        conn.exportedObject = client

        // Pin the daemon's code signature (LOCAL_DEV self-signed / RELEASE Developer ID).
        let mode = HelperConstants.activeSigningMode
        try? conn.setCodeSigningRequirement(HelperConstants.helperRequirement(for: mode))

        conn.invalidationHandler = { [weak self] in
            self?.queue.async { self?.connection = nil }
        }
        conn.interruptionHandler = { [weak self] in
            self?.queue.async { self?.connection = nil }
        }
        conn.resume()
        return conn
    }

    private func proxy(_ onError: @escaping (Error) -> Void) -> RoutingProtocol? {
        queue.sync {
            if connection == nil { connection = makeConnection() }
            return connection?.remoteObjectProxyWithErrorHandler { err in
                onError(err)
            } as? RoutingProtocol
        }
    }

    func invalidate() {
        queue.sync {
            connection?.invalidate()
            connection = nil
        }
    }

    // MARK: - Typed async API

    enum XPCError: Error { case noProxy; case decodeFailed; case remote(String) }

    func getNetworkState() async throws -> NetworkStateDTO {
        try await withCheckedThrowingContinuation { cont in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            p.getNetworkState { data in
                guard let data,
                      let dto = try? JSONDecoder.routeMaster.decode(NetworkStateDTO.self, from: data)
                else { cont.resume(throwing: XPCError.decodeFailed); return }
                cont.resume(returning: dto)
            }
        }
    }

    func currentStatus() async throws -> StatusDTO {
        try await withCheckedThrowingContinuation { cont in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            p.currentStatus { data in
                guard let data,
                      let dto = try? JSONDecoder.routeMaster.decode(StatusDTO.self, from: data)
                else { cont.resume(throwing: XPCError.decodeFailed); return }
                cont.resume(returning: dto)
            }
        }
    }

    func getConfig() async throws -> AppConfig {
        try await withCheckedThrowingContinuation { cont in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            p.getConfig { data in
                guard let data,
                      let dto = try? JSONDecoder.routeMaster.decode(AppConfig.self, from: data)
                else { cont.resume(throwing: XPCError.decodeFailed); return }
                cont.resume(returning: dto)
            }
        }
    }

    func applyConfig(_ config: AppConfig) async throws {
        let data = try JSONEncoder.routeMaster.encode(config)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            p.applyConfig(data) { ok, err in
                ok ? cont.resume() : cont.resume(throwing: XPCError.remote(err ?? "applyConfig failed"))
            }
        }
    }

    func startEngine() async throws { try await boolCall { $0.startEngine(withReply: $1) } }
    func stopEngine() async throws { try await boolCall { $0.stopEngine(withReply: $1) } }
    func reresolveNow() async throws { try await boolCall { $0.reresolveNow(withReply: $1) } }

    func dryRunPreview() async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            p.runDryRunPreview { lines in cont.resume(returning: lines) }
        }
    }

    private func boolCall(
        _ body: @escaping (RoutingProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let p = proxy({ cont.resume(throwing: $0) }) else {
                cont.resume(throwing: XPCError.noProxy); return
            }
            body(p) { ok, err in
                ok ? cont.resume() : cont.resume(throwing: XPCError.remote(err ?? "call failed"))
            }
        }
    }
}
