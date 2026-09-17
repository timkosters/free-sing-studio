import SwiftUI
import SingwellCore

/// Brand palette carried over from the web app: violet for the voice, blue for the piano's
/// "listen" phase, green for "your turn" and hits.
extension Color {
    static let voice = Color(red: 0.439, green: 0.282, blue: 0.784)
    static let voiceSoft = Color(red: 0.780, green: 0.659, blue: 1.0)
    static let listenBlue = Color(red: 0.255, green: 0.404, blue: 0.835)
    static let singGreen = Color(red: 0.090, green: 0.502, blue: 0.357)
    static let warmAmber = Color(red: 0.86, green: 0.55, blue: 0.14)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// Small label + big value, used across the stats rows.
struct StatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint ?? .primary)
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorBanner: View {
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ProBadge: View {
    var body: some View {
        Label("Pro", systemImage: "lock.fill")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.voice.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.voice)
    }
}

/// Stepper that shows a note name, for roots and quest bounds.
struct NoteStepper: View {
    var title: String
    @Binding var midi: Int
    var range: ClosedRange<Int>
    var onPlay: ((Int) -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let onPlay {
                Button { onPlay(midi) } label: { Image(systemName: "speaker.wave.2") }
                    .buttonStyle(.borderless)
            }
            Stepper(value: $midi, in: range) {
                Text(Pitch.noteName(Double(midi)))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}

struct LiveDot: View {
    var color: Color = .red
    @State private var on = true
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = false }
    }
}

