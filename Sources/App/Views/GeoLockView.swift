import SwiftUI

struct GeoLockView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @State private var newDomain = ""
    @State private var newCountry = "TR"

    // A small, common subset; the field also accepts any ISO alpha-2 code.
    private let commonCountries = ["TR", "US", "DE", "GB", "NL", "FR", "IR", "AE", "CA", "SE"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Geo-Lock").font(.title.weight(.bold))
                Text("Each domain is only reachable when the VPN's external country matches. "
                     + "On violation the domain's IPs are blackholed (kill-switch).")
                    .font(.caption).foregroundStyle(.secondary)

                currentLocationCard
                addRow

                ForEach(vm.config.geoLockRules) { rule in
                    ruleCard(rule)
                }
            }
            .padding(24)
        }
    }

    private var currentLocationCard: some View {
        HStack {
            Image(systemName: "globe").font(.title2).foregroundStyle(Neon.purple)
            VStack(alignment: .leading) {
                Text("Current external location").font(.caption).foregroundStyle(.secondary)
                Text(vm.status?.externalCountry ?? "unknown").font(.headline)
            }
            Spacer()
            Text(vm.status?.externalIP ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .glassCard(glow: Neon.purple)
    }

    private var addRow: some View {
        HStack {
            TextField("domain (e.g. claude.ai)", text: $newDomain)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $newCountry) {
                ForEach(commonCountries, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 80)
            Button("Add") {
                vm.addGeoRule(domain: newDomain, country: newCountry)
                newDomain = ""
            }
            .buttonStyle(NeonButtonStyle(tint: Neon.green))
        }
        .glassCard(glow: Neon.green)
    }

    private func ruleCard(_ rule: GeoLockRule) -> some View {
        let status = vm.status?.geoLocks.first { $0.domain == rule.domain }
        let state = status?.state ?? .unknown
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.domain).font(.headline)
                Spacer()
                StatusBadge(text: badgeText(state), color: badgeColor(state))
                Button(role: .destructive) {
                    if let idx = vm.config.geoLockRules.firstIndex(of: rule) {
                        vm.removeGeoRules(at: [idx])
                    }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(Neon.red)
            }
            HStack {
                Text("Requires").font(.caption).foregroundStyle(.secondary)
                Text(rule.requiredCountry).font(.caption.weight(.bold))
                Spacer()
                if let black = status?.blackholedIPs, !black.isEmpty {
                    Label("\(black.count) blackholed", systemImage: "hand.raised.fill")
                        .font(.caption).foregroundStyle(Neon.red)
                }
            }
        }
        .glassCard(glow: badgeColor(state))
    }

    private func badgeText(_ s: GeoLockState) -> String {
        switch s {
        case .compliant: return "OK"
        case .violated:  return "TRIGGERED"
        case .unknown:   return "UNKNOWN"
        }
    }
    private func badgeColor(_ s: GeoLockState) -> Color {
        switch s {
        case .compliant: return Neon.green
        case .violated:  return Neon.red
        case .unknown:   return Neon.amber
        }
    }
}
