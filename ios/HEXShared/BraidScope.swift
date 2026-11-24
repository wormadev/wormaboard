import SwiftUI

/// WormaDev Experiments › Braid indicator: two tapered strands that braid open with the voice
/// while recording, and lie nearly flat with a knot travelling along them while transcribing.
/// Drawn after the wormadev mark's stroke: thin ends, full in the middle.
struct BraidScopeView: View {
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
        let height = size.height
        let start = leadingInset + height * 0.5
        let end = size.width - trailingInset - height * 0.5
        guard end > start else { return }
        let mid = height / 2
        let knot = phase == .processing ? (time * 0.45).truncatingRemainder(dividingBy: 1.2) - 0.1 : nil
        let open = motion.strength * (phase == .processing ? 1 : 0.25 + 0.75 * motion.level)

        for (sign, opacity) in [(1.0, 1.0), (-1.0, 0.45)] {
            let points = (0...64).map { i -> CGPoint in
                let u = Double(i) / 64
                var amplitude = sin(.pi * u) * height * 0.3 * open
                if let knot {
                    amplitude *= 0.35 + 0.65 * exp(-pow((u - knot) * 5, 2))
                }
                let y = mid + sign * amplitude * sin(u * .pi * 3.2 - time * 4)
                return CGPoint(x: start + (end - start) * u, y: y)
            }
            context.fill(
                Self.taperedPath(points) { u in 1.5 + sin(.pi * u) * height * 0.11 },
                with: .color(color.opacity(opacity))
            )
        }
    }

    /// A filled outline around `points`, `width(u)` wide at each point.
    private static func taperedPath(_ points: [CGPoint], width: (Double) -> Double) -> Path {
        let last = points.count - 1
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...last {
            let a = points[max(i - 1, 0)]
            let b = points[min(i + 1, last)]
            let length = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            let half = width(Double(i) / Double(last)) / 2
            let nx = -(b.y - a.y) / length * half
            let ny = (b.x - a.x) / length * half
            left.append(CGPoint(x: points[i].x + nx, y: points[i].y + ny))
            right.append(CGPoint(x: points[i].x - nx, y: points[i].y - ny))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
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
