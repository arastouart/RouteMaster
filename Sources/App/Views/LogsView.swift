import SwiftUI

struct LogsView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @State private var preview: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Logs & Status").font(.title.weight(.bold))

                HStack {
                    Button {
                        Task { preview = await vm.dryRunPreview() }
                    } label: { Label("Dry-run preview", systemImage: "eye") }
                        .buttonStyle(NeonButtonStyle(tint: Neon.blue))
                    Spacer()
                }

                if !preview.isEmpty {
                    section("Dry-run preview (commands that WOULD run)", preview, Neon.amber)
                }

                section("Recent ShellRunner commands",
                        vm.status?.recentCommands ?? [], Neon.green)

                section("Engine events (live)", vm.logLines.suffix(200).map { $0 }, Neon.purple)
            }
            .padding(24)
        }
    }

    private func section(_ title: String, _ lines: [String], _ glow: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if lines.isEmpty {
                Text("—").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .glassCard(glow: glow)
    }
}
