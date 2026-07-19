import SwiftUI

struct SplitRoutingView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @State private var newDomain = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Split Routing").font(.title.weight(.bold))
                    Spacer()
                    Button {
                        Task { await vm.reresolveNow() }
                    } label: { Label("Re-resolve now", systemImage: "arrow.clockwise") }
                        .buttonStyle(NeonButtonStyle(tint: Neon.blue))
                }

                Text("These domains egress the physical interface (bypassing the VPN). "
                     + "Resolution uses an interface-bound DNS query so CDN IPs match the ISP view.")
                    .font(.caption).foregroundStyle(.secondary)

                addRow

                ForEach(vm.config.splitDomains) { domain in
                    domainCard(domain)
                }
            }
            .padding(24)
        }
    }

    private var addRow: some View {
        HStack {
            TextField("add domain (e.g. bitgraph.ir)", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Add", action: add).buttonStyle(NeonButtonStyle(tint: Neon.green))
        }
        .glassCard(glow: Neon.green)
    }

    private func add() {
        vm.addSplitDomain(newDomain)
        newDomain = ""
    }

    private func domainCard(_ domain: RoutedDomain) -> some View {
        let status = vm.status?.domains.first { $0.domain == domain.domain }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(domain.domain).font(.headline)
                Spacer()
                Button(role: .destructive) {
                    if let idx = vm.config.splitDomains.firstIndex(of: domain) {
                        vm.removeSplitDomains(at: [idx])
                    }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(Neon.red)
            }
            if let status {
                labeled("Resolved IPs", status.resolvedIPs.isEmpty ? "—" : status.resolvedIPs.joined(separator: ", "))
                labeled("Active routes", status.activeRouteIPs.isEmpty ? "—" : status.activeRouteIPs.joined(separator: ", "))
            } else {
                Text("no resolution yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .glassCard(glow: Neon.blue)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.caption.monospaced())
            Spacer()
        }
    }
}
