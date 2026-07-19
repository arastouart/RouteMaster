import SwiftUI

/// MenuBarExtra content: quick Start/Stop, VPN location/country, Geo-Lock summary.
struct MenuBarView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @Environment(\.openWindow) private var openWindow

    private var geoState: GeoLockState {
        let states = vm.status?.geoLocks.map(\.state) ?? []
        if states.contains(.violated) { return .violated }
        if states.contains(.compliant) { return .compliant }
        return .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RouteMaster").font(.headline)
                Spacer()
                StatusBadge(text: vm.engineRunning ? "RUNNING" : "STOPPED",
                            color: vm.engineRunning ? Neon.green : Neon.amber)
            }

            Divider()

            HStack {
                Image(systemName: "globe").foregroundStyle(Neon.purple)
                Text("Location")
                Spacer()
                Text(vm.status?.externalCountry ?? "—").font(.body.weight(.semibold))
            }

            HStack {
                Image(systemName: "network")
                Text("VPN")
                Spacer()
                StatusBadge(text: (vm.status?.network.vpnActive ?? false) ? "UP" : "DOWN",
                            color: (vm.status?.network.vpnActive ?? false) ? Neon.green : Neon.amber)
            }

            HStack {
                Image(systemName: "lock.shield").foregroundStyle(Neon.blue)
                Text("Geo-Lock")
                Spacer()
                StatusBadge(text: geoBadge, color: geoColor)
            }

            if vm.config.dryRun {
                Label("Dry-run ON", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(Neon.green)
            } else {
                Label("Dry-run OFF — LIVE", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Neon.red)
            }

            Divider()

            HStack {
                Button(vm.engineRunning ? "Stop" : "Start") {
                    Task { vm.engineRunning ? await vm.stopEngine() : await vm.startEngine() }
                }
                .buttonStyle(NeonButtonStyle(tint: vm.engineRunning ? Neon.red : Neon.green))
                Spacer()
                Button("Open") { openWindow(id: "main") }
            }

            Button("Quit RouteMaster") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var geoBadge: String {
        switch geoState {
        case .compliant: return "OK"
        case .violated:  return "TRIGGERED"
        case .unknown:   return "—"
        }
    }
    private var geoColor: Color {
        switch geoState {
        case .compliant: return Neon.green
        case .violated:  return Neon.red
        case .unknown:   return Neon.amber
        }
    }
}
