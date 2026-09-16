import UIKit

/// Small, consistent haptic vocabulary. Every call checks the user preference first.
@MainActor
enum Haptics {
    static var enabled = true

    static func hit() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func beat(accent: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: accent ? .medium : .soft).impactOccurred(intensity: accent ? 1 : 0.6)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
