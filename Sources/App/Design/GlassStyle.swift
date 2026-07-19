import SwiftUI

/// Liquid-Glass / glassmorphism + neon-dark design language. Works in Dark and Light:
/// Light uses stronger borders for contrast; Dark uses deeper neon shadows.
enum Neon {
    static let blue = Color(red: 0.30, green: 0.70, blue: 1.00)
    static let purple = Color(red: 0.62, green: 0.42, blue: 1.00)
    static let green = Color(red: 0.30, green: 0.95, blue: 0.65)
    static let red = Color(red: 1.00, green: 0.35, blue: 0.45)
    static let amber = Color(red: 1.00, green: 0.75, blue: 0.30)
}

/// A frosted glass card with a soft neon glow and a hairline stroke.
struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var glow: Color = Neon.blue
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(scheme == .dark ? 0.20 : 0.45),
                        lineWidth: scheme == .dark ? 1 : 1.5
                    )
            )
            .shadow(
                color: glow.opacity(scheme == .dark ? 0.35 : 0.18),
                radius: scheme == .dark ? 20 : 10,
                x: 0, y: 6
            )
    }
}

extension View {
    func glassCard(glow: Color = Neon.blue, cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(glow: glow, cornerRadius: cornerRadius))
    }
}

/// App background: a deep gradient with faint neon orbs behind the glass.
struct NeonBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.04, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.06, blue: 0.16)]
                    : [Color(red: 0.90, green: 0.93, blue: 0.98), Color(red: 0.85, green: 0.88, blue: 0.96)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Neon.purple.opacity(scheme == .dark ? 0.25 : 0.12))
                .frame(width: 320).blur(radius: 120).offset(x: -160, y: -200)
            Circle().fill(Neon.blue.opacity(scheme == .dark ? 0.22 : 0.10))
                .frame(width: 360).blur(radius: 140).offset(x: 180, y: 220)
        }
        .ignoresSafeArea()
    }
}

/// A small pill status badge (OK / TRIGGERED / VPN state).
struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
            .foregroundStyle(color)
    }
}

/// Primary neon button style.
struct NeonButtonStyle: ButtonStyle {
    var tint: Color = Neon.blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.35 : 0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.7), lineWidth: 1)
            )
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.4), radius: configuration.isPressed ? 4 : 12)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
