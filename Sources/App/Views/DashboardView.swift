import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @Binding var path: NavigationPath
    @State private var showDryRunConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                engineCard
                statusCard
                dryRunCard
                navButtons
                if let err = vm.lastError {
                    Text(err).font(.caption).foregroundStyle(Neon.amber)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showDryRunConfirm) {
            DryRunConfirmSheet {
                vm.dryRunDisableConfirmed = true
                vm.setDryRun(false)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title).foregroundStyle(Neon.blue)
            VStack(alignment: .leading) {
                Text("RouteMaster").font(.title.weight(.bold))
                Text("Split-routing & Geo-Lock").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: vm.connected ? "DAEMON OK" : "DAEMON OFF",
                        color: vm.connected ? Neon.green : Neon.red)
        }
    }

    private var engineCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Engine").font(.headline)
                Text(vm.engineRunning ? "Running" : "Stopped")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isHelperEnabled {
                Button("Install Helper") { vm.installHelper() }
                    .buttonStyle(NeonButtonStyle(tint: Neon.purple))
            }
            Button(vm.engineRunning ? "Stop" : "Start") {
                Task { vm.engineRunning ? await vm.stopEngine() : await vm.startEngine() }
            }
            .buttonStyle(NeonButtonStyle(tint: vm.engineRunning ? Neon.red : Neon.green))
        }
        .glassCard(glow: vm.engineRunning ? Neon.green : Neon.blue)
    }

    private var statusCard: some View {
        let net = vm.status?.network
        return VStack(alignment: .leading, spacing: 10) {
            Text("Live Status").font(.headline)
            row("Physical interface", net?.physicalInterface ?? "—")
            row("Physical gateway", net?.physicalGateway ?? "—")
            row("Default interface", net?.defaultInterface ?? "—")
            HStack {
                Text("VPN").foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: (net?.vpnActive ?? false) ? "UP" : "DOWN",
                            color: (net?.vpnActive ?? false) ? Neon.green : Neon.amber)
            }
            HStack {
                Text("External country").foregroundStyle(.secondary)
                Spacer()
                Text(vm.status?.externalCountry ?? "—").font(.body.weight(.semibold))
            }
        }
        .glassCard(glow: Neon.blue)
    }

    private var dryRunCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dry-Run").font(.headline)
                    Text(vm.config.dryRun
                         ? "Safe: route commands are previewed, never executed."
                         : "LIVE: route commands mutate the system routing table.")
                        .font(.caption)
                        .foregroundStyle(vm.config.dryRun ? .secondary : Neon.red)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.config.dryRun },
                    set: { newValue in
                        if newValue == false {
                            // Turning dry-run OFF always requires explicit confirmation.
                            showDryRunConfirm = true
                        } else {
                            vm.setDryRun(true)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Neon.green)
            }
            if !vm.config.dryRun {
                Label("A wrong host route can drop connectivity. Recover with "
                      + "`sudo route delete -host <ip>` or reboot.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Neon.amber)
            }
        }
        .glassCard(glow: vm.config.dryRun ? Neon.green : Neon.red)
    }

    private var navButtons: some View {
        HStack(spacing: 12) {
            navButton("Split Routing", "arrow.triangle.branch", Neon.blue, .splitRouting)
            navButton("Geo-Lock", "lock.shield", Neon.purple, .geoLock)
            navButton("Logs", "list.bullet.rectangle", Neon.green, .logs)
        }
    }

    private func navButton(_ title: String, _ icon: String, _ tint: Color, _ screen: Screen) -> some View {
        Button { path.append(screen) } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonButtonStyle(tint: tint))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.medium))
        }
    }

    private var isHelperEnabled: Bool { vm.installer.state == .enabled }
}

/// Explicit confirmation before ever leaving dry-run (checkbox + typed acknowledgment).
struct DryRunConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var typed = ""
    let onConfirm: () -> Void

    private var canDisable: Bool { acknowledged && typed.uppercased() == "DISABLE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Disable Dry-Run?", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.bold)).foregroundStyle(Neon.red)

            Text("""
            Leaving dry-run lets RouteMaster mutate the LIVE routing table. A wrong or \
            stale host route can drop your connectivity.

            To recover if something goes wrong:
              • sudo route delete -host <ip>
              • or reboot — volatile host routes are cleared on restart.
            """)
            .font(.callout).foregroundStyle(.secondary)

            Toggle("I understand this changes live system routing.", isOn: $acknowledged)
                .toggleStyle(.checkbox)

            HStack {
                Text("Type").foregroundStyle(.secondary)
                TextField("DISABLE", text: $typed).textFieldStyle(.roundedBorder).frame(width: 140)
                Text("to confirm").foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Disable Dry-Run") { onConfirm(); dismiss() }
                    .buttonStyle(NeonButtonStyle(tint: Neon.red))
                    .disabled(!canDisable)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(NeonBackground())
    }
}
