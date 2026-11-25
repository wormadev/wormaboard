import SwiftUI

/// The dictation indicator in the waveform picked in Settings › Dictation: Hex's Metal dot
/// scope, or one of the stroke waveforms (`BraidScopeView`).
struct DictationWaveView: View {
    var phase: DotScopePhase
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var color: Color = .white
    var loudnessProvider: () -> Float

    @AppStorage(DictationWaveform.key, store: UserDefaults(suiteName: KeyboardBridge.appGroup))
    private var waveform: DictationWaveform = .braid

    var body: some View {
        if waveform == .hex {
            DotScopeView(
                phase: phase,
                tuning: .bar(leadingInset: Float(leadingInset), trailingInset: Float(trailingInset), fade: 28.0, spacing: 3.5),
                drawPlate: false,
                loudnessProvider: loudnessProvider
            )
            .clipShape(Capsule())
        } else {
            BraidScopeView(
                waveform: waveform,
                phase: phase,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                color: color,
                loudnessProvider: loudnessProvider
            )
        }
    }
}

/// The stroke waveforms, live: they swing open with the voice while recording, and lie
/// nearly flat with a knot (swell, crawling worm) travelling along them while transcribing.
struct BraidScopeView: View {
    var waveform: DictationWaveform = .braid
    var phase: DotScopePhase
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var color: Color = .white
    var loudnessProvider: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = BraidMotion()

    private var animates: Bool {
        switch phase {
        case .starting, .recording, .processing: true
        case .hidden, .idle, .failed: false
        }
    }

    var body: some View {
        TimelineView(.animation(paused: !animates)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                motion.advance(to: time, strength: targetStrength, level: level, eases: animates)
                draw(in: &context, size: size, time: reduceMotion ? time * 0.4 : time)
            }
        }
        .opacity(phase == .hidden ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var targetStrength: Double {
        switch phase {
        case .recording: 1
        case .processing: 0.6
        case .starting: 0.3
        case .hidden, .idle, .failed: 0.08
        }
    }

    /// Hex's loudness (dBFS, -62 or lower in silence) as 0...1.
    private var level: Double {
        guard phase == .recording else { return 0 }
        return min(1, max(0, (Double(loudnessProvider()) + 55) / 40))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let knot = phase == .processing ? (time * 0.45).truncatingRemainder(dividingBy: 1.2) - 0.1 : nil
        WaveStrokes.draw(
            waveform,
            in: &context,
            from: leadingInset + size.height * 0.5,
            to: size.width - trailingInset - size.height * 0.5,
            height: size.height,
            open: motion.strength * (phase == .processing ? 1 : 0.25 + 0.75 * motion.level),
            time: time,
            knot: knot,
            color: color
        )
    }
}

/// The braid's eased strength and level, kept across frames so phase and voice changes glide.
private final class BraidMotion {
    var strength = 0.08
    var level = 0.0
    private var lastTime: Double?

    /// Without `eases` (a paused timeline) it lands at once, so no frame is left half-way.
    func advance(to time: Double, strength target: Double, level heard: Double, eases: Bool) {
        let dt = eases ? lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0 : 1
        lastTime = eases ? time : nil
        strength += (target - strength) * min(1, dt * 6)
        level += (heard - level) * min(1, dt * 12)
    }
}
