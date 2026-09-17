import SwiftUI
import SingwellCore

/// The web app's design tokens, one for one. Light and dark values come from its `:root` and `.dark`.
extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    /// Primary teal-green: buttons, the live trail, hits.
    static let voice = dyn(0x0f766e, 0x2dd4bf)
    static let singGreen = dyn(0x0f766e, 0x2dd4bf)
    /// Gold: targets and the piano's "listen" phase.
    static let listenBlue = dyn(0xa07708, 0xf0b429)
    static let warmAmber = dyn(0xa07708, 0xf0b429)
    /// Violet: the synthetic demo voice only.
    static let voiceSoft = dyn(0x7048c8, 0xc7a8ff)
    static let demoViolet = dyn(0x7048c8, 0xc7a8ff)
    static let band = dyn(0xfbeecd, 0x2c2618)
    static let pageBackground = dyn(0xeef1f4, 0x0e1417)
    static let cardBackground = dyn(0xffffff, 0x161e22)
    static let plot = dyn(0xf7f9fb, 0x111a1e)
    static let muted = dyn(0xe2e7ed, 0x1e282d)
    static let mutedForeground = dyn(0x5b6673, 0x9aabb2)
    static let ink = dyn(0x12161c, 0xe9eff1)
    static let hairline = dyn(0xd5dce4, 0x2a373d)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Fraunces for display, Sora for everything else, scaled with Dynamic Type.
extension Font {
    static func display(_ style: TextStyle) -> Font {
        .custom("Fraunces-Light", size: UIFont.preferredFont(forTextStyle: style.uiKit).pointSize, relativeTo: style)
    }
    static func display(size: CGFloat) -> Font { .custom("Fraunces-Light", size: size) }
    static func sora(_ style: TextStyle, _ weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Sora-SemiBold"
        case .medium: name = "Sora-Medium"
        default: name = "Sora-Regular"
        }
        return .custom(name, size: UIFont.preferredFont(forTextStyle: style.uiKit).pointSize, relativeTo: style)
    }
    static func sora(size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black: return .custom("Sora-SemiBold", size: size)
        case .medium: return .custom("Sora-Medium", size: size)
        default: return .custom("Sora-Regular", size: size)
        }
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
            .shadow(color: Color.ink.opacity(0.04), radius: 1, y: 1)
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
                .font(.sora(.caption2, .semibold))
                .foregroundStyle(Color.mutedForeground)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.display(.title2))
                    .monospacedDigit()
                    .foregroundStyle(tint ?? .primary)
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.sora(.caption)).foregroundStyle(Color.mutedForeground) }
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warmAmber)
            Text(message).font(.sora(.footnote))
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }.buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.band, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProBadge: View {
    var body: some View {
        Label("Pro", systemImage: "lock.fill")
            .font(.sora(.caption2, .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.voice.opacity(0.12), in: Capsule())
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
                Button { onPlay(midi) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
            }
            Stepper(value: $midi, in: range) {
                Text(Pitch.noteName(Double(midi))).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
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

/// The wordmark: four bars and the name in Fraunces, as on the web.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach([10, 16, 22, 14, 8], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.voice).frame(width: 3, height: CGFloat(h))
                }
            }
            Text("Singwell").font(.custom("Fraunces-Medium", size: 22))
        }
    }
}
