import Foundation

/// Wires a `GeoLockLoop` into the `RoutingService`: exposes geo status/external/blackhole
/// data for `currentStatus`/`runDryRunPreview`, and starts/stops the loop in lockstep
/// with the engine. Also forwards committed state changes to the app so it can post a
/// `UNUserNotification` (the daemon cannot post notifications itself).
enum GeoLockWiring {
    static func attach(to service: RoutingService, shell: ShellRunner,
                       configStore: ConfigStore, inspector: NetworkInspector,
                       routeManager: RouteManager) {

        let geo = GeoLockLoop(shell: shell, configStore: configStore,
                              inspector: inspector, routeManager: routeManager)

        // Surface geo data into the status/preview paths.
        service.geoStatuses = { geo.statuses() }
        service.geoExternal = { geo.external() }
        service.desiredBlackholeIPs = { geo.desiredBlackholeIPs() }

        // Start/stop with the engine.
        service.onStart = { geo.start() }
        service.onStop = { geo.stop(liftBlackholes: true) }

        // Daemon -> app callback for notifications.
        geo.onStateChange = { [weak service] domain, state, country in
            service?.clientProxy?.geoLockDidChange(
                domain: domain, stateRaw: state.rawValue, country: country)
            service?.clientProxy?.engineDidLog(
                "[geo] \(domain) -> \(state.rawValue) (country=\(country ?? "?"))")
        }
    }
}
