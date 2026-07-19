import Foundation

/// Phase 3 placeholder. Phase 4 replaces this with real wiring that attaches a
/// `GeoLockLoop` to the service (external-country checks + blackhole kill-switch).
///
/// Keeping the hook here lets `main.swift` stay unchanged across phases.
enum GeoLockWiring {
    static func attach(to service: RoutingService, shell: ShellRunner,
                       configStore: ConfigStore, inspector: NetworkInspector,
                       routeManager: RouteManager) {
        // no-op until Phase 4
    }
}
