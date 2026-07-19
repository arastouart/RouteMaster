import Foundation

// ---------------------------------------------------------------------------
// RouteMasterHelper — privileged daemon entry point.
//
// Vends the RoutingProtocol Mach service. Every incoming connection is validated
// against the APP's code-signing requirement (macOS 13 setCodeSigningRequirement);
// there is NO custom auth handshake. The process is kept alive with dispatchMain().
//
// SAFETY: the engine starts in the dry-run state persisted in config.json (dryRun
// defaults to true). Nothing mutates the routing table until the app explicitly
// disables dry-run AND the user confirms.
// ---------------------------------------------------------------------------

func log(_ message: String) {
    FileHandle.standardError.write(Data("RouteMasterHelper: \(message)\n".utf8))
}

// Assemble the daemon's object graph.
let configStore = ConfigStore()
let shell = ShellRunner(dryRun: configStore.snapshot().dryRun)
let inspector = NetworkInspector(shell: shell)
let routeManager = RouteManager(shell: shell)
let engine = EngineLoop(shell: shell, inspector: inspector,
                        routeManager: routeManager, configStore: configStore)
let service = RoutingService(shell: shell, configStore: configStore, inspector: inspector,
                             routeManager: routeManager, engine: engine)

// Phase 4 wires the Geo-Lock loop into `service` here.
GeoLockWiring.attach(to: service, shell: shell, configStore: configStore,
                     inspector: inspector, routeManager: routeManager)

/// Validates and configures each incoming XPC connection.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: RoutingService
    init(service: RoutingService) { self.service = service }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Pin the connecting app's code signature (LOCAL_DEV self-signed / RELEASE Dev ID).
        let mode = HelperConstants.activeSigningMode
        let requirement = HelperConstants.appRequirement(for: mode)
        do {
            try connection.setCodeSigningRequirement(requirement)
        } catch {
            log("rejecting connection: setCodeSigningRequirement failed: \(error)")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: RoutingProtocol.self)
        connection.exportedObject = service

        // Interface for daemon->app callbacks (notifications, log streaming).
        connection.remoteObjectInterface = NSXPCInterface(with: RoutingClientProtocol.self)
        service.clientProxy = connection.remoteObjectProxy as? RoutingClientProtocol

        connection.invalidationHandler = { [weak service] in
            service?.clientProxy = nil
        }
        connection.resume()
        log("accepted validated connection (mode=\(mode.rawValue))")
        return true
    }
}

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

log("listening on \(HelperConstants.machServiceName) (dryRun=\(shell.dryRun))")
dispatchMain()
