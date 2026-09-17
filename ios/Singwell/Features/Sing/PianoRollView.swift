import SwiftUI
import SingwellCore

/// The chromatic piano roll: keys on the left, time flowing right to left, your pitch as a
/// violet trail, the target as a dashed line. Works for the live trail and take replay.
struct PianoRollView: View {
    var frames: [PitchFrame]
    /// Right-edge time in the frames' time base.
    var now: Double
    var window: Double = 10
    var currentMidi: Double?
    var target: Int?
    var playedNote: Int?
    var follow: Bool = true
    var demo: Bool = false
    var onKeyTap: ((Int) -> Void)? = nil

    @State private var center: Double = 60
    private let keyWidth: CGFloat = 46
    private let followSpan: Double = 30 // semitones visible when following

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                Canvas(rendersAsynchronously: false) { context, size in
                    draw(in: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard location.x <= keyWidth, let onKeyTap else { return }
                onKeyTap(midi(atY: location.y, height: geo.size.height))
            }
        }
        .background(Color.plot)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
        .onChange(of: currentMidi) { _, new in
            if let new, follow { withAnimation(.easeOut(duration: 0.35)) { center = new } }
        }
        .accessibilityLabel("Piano roll showing your pitch over the last \(Int(window)) seconds")
    }

    private var bounds: (low: Double, high: Double) {
        if follow {
            let goal = currentMidi ?? center
            let c = max(36 + followSpan / 2 - 6, min(84 - followSpan / 2 + 6, goal))
            return (c - followSpan / 2, c + followSpan / 2)
        }
        let b = Pitch.chartBounds(frames.compactMap { $0.midi } + (target.map { [Double($0)] } ?? []))
        return (Double(b.low), Double(b.high))
    }

    private func y(for midi: Double, height: CGFloat, bounds: (low: Double, high: Double)) -> CGFloat {
        let span = bounds.high - bounds.low
        return height * CGFloat(1 - (midi - bounds.low) / span)
    }

    private func midi(atY y: CGFloat, height: CGFloat) -> Int {
        let b = bounds
        let span = b.high - b.low
        return Int((b.high - Double(y / height) * span).rounded())
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let b = bounds
        let laneHeight = size.height / CGFloat(b.high - b.low)
        let plotX = keyWidth
        let plotWidth = size.width - keyWidth
        let scheme = context.environment.colorScheme

        // Lanes and keys
        let lowNote = Int(b.low.rounded(.down)), highNote = Int(b.high.rounded(.up))
        for note in lowNote...highNote {
            let top = y(for: Double(note) + 0.5, height: size.height, bounds: b)
            let rect = CGRect(x: 0, y: top, width: size.width, height: laneHeight)
            let black = Pitch.isBlackKey(note)
            let laneColor: Color = black ? Color.primary.opacity(scheme == .dark ? 0.06 : 0.045) : Color.clear
            context.fill(Path(rect), with: .color(laneColor))
            if let current = currentMidi, Int(current.rounded()) == note {
                context.fill(Path(CGRect(x: keyWidth, y: top, width: size.width - keyWidth, height: laneHeight)), with: .color((demo ? Color.demoViolet : Color.voice).opacity(0.14)))
            }
            let keyRect = CGRect(x: 0, y: top, width: keyWidth, height: laneHeight)
            let accent: Color = demo ? .demoViolet : .voice
            var keyColor: Color = black ? Color.ink : Color.cardBackground
            if let current = currentMidi, Int(current.rounded()) == note { keyColor = accent.opacity(0.85) }
            if playedNote == note { keyColor = accent }
            if let target, target == note { keyColor = .warmAmber.opacity(0.85) }
            context.fill(Path(roundedRect: keyRect.insetBy(dx: 2, dy: 0.5), cornerRadius: 3), with: .color(keyColor))
            if note % 12 == 0 || laneHeight >= 13 {
                let label = Text(Pitch.noteName(Double(note)))
                    .font(.system(size: min(11, max(7, laneHeight * 0.7)), weight: note % 12 == 0 ? .bold : .regular, design: .rounded))
                    .foregroundColor(black || (currentMidi.map { Int($0.rounded()) == note } ?? false) || playedNote == note || target == note ? (scheme == .dark && !black ? .black : .white) : (scheme == .dark ? .white : .black))
                context.draw(label, at: CGPoint(x: keyWidth / 2, y: top + laneHeight / 2), anchor: .center)
            }
            if note % 12 == 0 {
                var line = Path()
                line.move(to: CGPoint(x: plotX, y: top + laneHeight))
                line.addLine(to: CGPoint(x: size.width, y: top + laneHeight))
                context.stroke(line, with: .color(Color.primary.opacity(0.18)), lineWidth: 1)
            }
        }

        // Grid: one line per second
        for s in 0...Int(window) {
            let x = plotX + plotWidth * CGFloat(1 - Double(s) / window)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(Color.primary.opacity(0.05)), lineWidth: 1)
        }

        func x(for t: Double) -> CGFloat { plotX + plotWidth * CGFloat(1 - (now - t) / window) }

        // Target line segments
        var targetPath = Path()
        var previousTarget: PitchFrame?
        for f in frames where f.target != nil {
            let p = CGPoint(x: x(for: f.t), y: y(for: f.target!, height: size.height, bounds: b))
            if let prev = previousTarget, prev.target == f.target, f.t - prev.t < 0.4 { targetPath.addLine(to: p) } else { targetPath.move(to: p) }
            previousTarget = f
        }
        if let target {
            let ty = y(for: Double(target), height: size.height, bounds: b)
            var live = Path(); live.move(to: CGPoint(x: plotX, y: ty)); live.addLine(to: CGPoint(x: size.width, y: ty))
            context.stroke(live, with: .color(Color.warmAmber.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        context.stroke(targetPath, with: .color(Color.warmAmber.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))

        // Pitch trail
        var trail = Path()
        var previous: PitchFrame?
        for f in frames {
            guard let m = f.midi else { previous = nil; continue }
            let p = CGPoint(x: x(for: f.t), y: y(for: m, height: size.height, bounds: b))
            if let prev = previous, prev.midi != nil, f.t - prev.t < 0.3 { trail.addLine(to: p) } else { trail.move(to: p) }
            previous = f
        }
        let trailColor: Color = demo ? .demoViolet : .voice
        context.stroke(trail, with: .color(trailColor.opacity(0.25)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        context.stroke(trail, with: .color(trailColor), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // Now marker and current pitch dot
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: size.width - 1, y: 0)); nowLine.addLine(to: CGPoint(x: size.width - 1, y: size.height))
        context.stroke(nowLine, with: .color(Color.primary.opacity(0.15)), lineWidth: 2)
        if let currentMidi {
            let p = CGPoint(x: size.width - 4, y: y(for: currentMidi, height: size.height, bounds: b))
            let inTune = target.map { abs(currentMidi - Double($0)) * 100 <= 50 } ?? false
            context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color((inTune ? Color.singGreen : trailColor).opacity(0.35)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(inTune ? .singGreen : trailColor))
        }
    }
}
