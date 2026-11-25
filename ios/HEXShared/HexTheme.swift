import SwiftUI

enum HexTheme {
    // OpenCode dark palette — single cool-neutral temperature, tints via opacity.
    static let bgDeep = Color(red: 0x0A / 255.0, green: 0x0B / 255.0, blue: 0x0D / 255.0)
    static let bgBase = Color(red: 0x11 / 255.0, green: 0x13 / 255.0, blue: 0x16 / 255.0)
    static let layer01 = Color(red: 0x17 / 255.0, green: 0x19 / 255.0, blue: 0x1D / 255.0)
    static let layer02 = Color(red: 0x20 / 255.0, green: 0x23 / 255.0, blue: 0x29 / 255.0)

    static let textBase = Color.white.opacity(0.94)
    static let textMuted = Color.white.opacity(0.56)
    static let textFaint = Color.white.opacity(0.36)

    static let borderWeak = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.11)

    static let bgContrast = Color.white.opacity(0.96)
    static let textContrast = Color(red: 0x0A / 255.0, green: 0x0B / 255.0, blue: 0x0D / 255.0)

    static let danger = Color(red: 0xE5 / 255.0, green: 0x4D / 255.0, blue: 0x42 / 255.0)
    static let dangerSurface = Color(red: 0xE5 / 255.0, green: 0x4D / 255.0, blue: 0x42 / 255.0).opacity(0.14)
    static let warmMic = Color(red: 0xFF / 255.0, green: 0x95 / 255.0, blue: 0x00 / 255.0)
    static let success = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)

    static let warmPearl = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let agentBlue = Color(red: 0.78, green: 0.86, blue: 0.97)

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 8.5

    static func formatClock(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds))
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(seconds)))
        if clamped >= 3600 {
            let mins = (clamped % 3600) / 60
            return mins == 0 ? "\(clamped / 3600)h" : "\(clamped / 3600)h \(mins)m"
        }
        if clamped >= 90 {
            return "\((clamped + 59) / 60)m"
        }
        return formatClock(TimeInterval(clamped))
    }
}

/// Critically damped `(duration, bounce: 0)` springs shared across Hex iPhone surfaces.
enum HexMotion {
    static let stageDuration: Double = 0.28
    static let settleDuration: Double = 0.30
    static let trayDuration: Double = 0.25
    static let reducedDuration: Double = 0.18

    static let stage = Animation.spring(duration: stageDuration, bounce: 0.0)
    static let settle = Animation.spring(duration: settleDuration, bounce: 0.0)
    static let tray = Animation.spring(duration: trayDuration, bounce: 0.0)
    static let reducedFade = Animation.easeInOut(duration: reducedDuration)

    static func stageAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : stage
    }

    static func settleAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : settle
    }

    static func trayAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : tray
    }
}

/// Keeps a control permanently mounted and drives its visibility continuously via
/// opacity, subtle scale (`>= 0.90`), and soft blur (`<= 4 pt`), so interrupted
/// transitions retarget velocity smoothly and never flash in or out in one frame.
struct HexControlReveal: ViewModifier {
    var shown: Bool
    var reduceMotion: Bool
    var scale: CGFloat = 0.92
    var blur: CGFloat = 2.5
    var anchor: UnitPoint = .center

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .opacity(shown ? 1.0 : 0.0)
            .scaleEffect(shown || reduceMotion ? 1.0 : scale, anchor: anchor)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
        if blur > 0 {
            base.blur(radius: (shown || reduceMotion) ? 0.0 : blur)
        } else {
            base
        }
    }
}

/// Keeps a top-bar tray or status item permanently mounted in a `ZStack` and
/// reveals it smoothly without layout jumps.
struct HexTrayReveal: ViewModifier {
    var shown: Bool
    var reduceMotion: Bool
    var offsetY: CGFloat = 3.5

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1.0 : 0.0)
            .offset(y: (shown || reduceMotion) ? 0.0 : offsetY)
            .blur(radius: (shown || reduceMotion) ? 0.0 : 2.5)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }
}

/// Soft recessed capsule well for `DotScopeView` that adapts naturally to both
/// dark and light host platters without opaque black holes or heavy box strokes.
struct HexRecessedWell: View {
    var isDark: Bool

    var body: some View {
        Capsule()
            .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.055))
            .overlay(alignment: .top) {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(isDark ? 0.30 : 0.09),
                                Color.clear,
                                Color.white.opacity(isDark ? 0.065 : 0.50),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
    }
}

extension View {
    func hexControlReveal(
        _ shown: Bool,
        reduceMotion: Bool,
        scale: CGFloat = 0.92,
        blur: CGFloat = 2.5,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(
            HexControlReveal(
                shown: shown,
                reduceMotion: reduceMotion,
                scale: scale,
                blur: blur,
                anchor: anchor
            )
        )
    }

    func hexTrayReveal(_ shown: Bool, reduceMotion: Bool, offsetY: CGFloat = 3.5) -> some View {
        modifier(HexTrayReveal(shown: shown, reduceMotion: reduceMotion, offsetY: offsetY))
    }

    /// Soft horizontal fade mask on scroll strips so chips never crop hard at edges.
    func hexHorizontalEdgeFade(leading: CGFloat = 14, trailing: CGFloat = 18) -> some View {
        mask {
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let l = min(0.25, max(0, leading / w))
                let r = max(0.75, min(1, 1 - trailing / w))
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: l),
                        .init(color: .black, location: r),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }
}

struct HexStatusDot: View {
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// The app icon's mark: the wormadev worm followed by a text cursor
/// (`ios/HEXMobile/AppIcon.icon`), in the worm's own 107 x 66 units.
enum WormaMark {
    private static let width: CGFloat = 128
    private static let cursorX: CGFloat = 121.2
    private static let cursorWidth: CGFloat = 6.8
    private static let cursorTop: CGFloat = -8.8
    private static let cursorHeight: CGFloat = 84
    private static let wormWidth: CGFloat = 107
    private static let wormHeight: CGFloat = 66
    private static let start = CGPoint(x: 90.72, y: 3.16)
    private static let curves: [[CGFloat]] = [
        [86.61, 8.34, 86.28, 15.54, 84.33, 21.70],
        [81.46, 30.54, 74.96, 51.54, 64.13, 40.23],
        [59.71, 35.54, 56.80, 28.96, 52.38, 24.33],
        [47.48, 18.91, 41.73, 20.72, 37.70, 26.07],
        [33.37, 31.37, 29.66, 38.31, 25.23, 43.69],
        [16.52, 54.24, 9.99, 49.85, 2.59, 40.95],
        [1.19, 39.48, 0.22, 38.88, 0.00, 39.58],
        [-0.10, 42.51, 1.92, 46.19, 3.16, 49.19],
        [6.52, 56.41, 12.04, 65.84, 19.41, 64.42],
        [27.64, 62.58, 31.98, 54.32, 38.03, 49.17],
        [43.14, 44.35, 47.95, 44.61, 52.57, 50.02],
        [58.51, 56.78, 65.44, 68.47, 75.57, 64.16],
        [87.51, 60.05, 111.48, 18.74, 105.05, 4.73],
        [102.53, -0.75, 94.55, -1.62, 90.84, 3.04],
    ]

    /// The worm and its cursor, fitted and centred in `rect`.
    static func paths(in rect: CGRect) -> (worm: CGPath, cursor: CGPath) {
        let s = min(rect.width / width, rect.height / cursorHeight)
        let origin = CGPoint(x: rect.midX - width * s / 2, y: rect.midY - cursorHeight * s / 2 - cursorTop * s)
        let barWidth = max(1.2, cursorWidth * s)
        let bar = CGRect(x: origin.x + cursorX * s, y: origin.y + cursorTop * s, width: barWidth, height: cursorHeight * s)
        let corner = min(0.6 * s, barWidth / 2)
        let cursor = CGPath(roundedRect: bar, cornerWidth: corner, cornerHeight: corner, transform: nil)
        return (worm(scale: s, origin: origin), cursor)
    }

    /// The worm alone, fitted and centred in `rect`.
    static func worm(in rect: CGRect) -> CGPath {
        let s = min(rect.width / wormWidth, rect.height / wormHeight)
        return worm(scale: s, origin: CGPoint(x: rect.midX - wormWidth * s / 2, y: rect.midY - wormHeight * s / 2))
    }

    private static func worm(scale s: CGFloat, origin: CGPoint) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
        let path = CGMutablePath()
        path.move(to: point(start.x, start.y))
        for c in curves {
            path.addCurve(to: point(c[4], c[5]), control1: point(c[0], c[1]), control2: point(c[2], c[3]))
        }
        path.closeSubpath()
        return path
    }
}

/// The app's brand mark (`WormaMark`); `coreColor` tints the cursor.
struct HexMarkView: View {
    var size: CGFloat = 20
    var color: Color = HexTheme.textBase
    var coreColor: Color? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let mark = WormaMark.paths(in: CGRect(origin: .zero, size: canvasSize))
            context.fill(Path(mark.worm), with: .color(color))
            context.fill(Path(mark.cursor), with: .color(coreColor ?? color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Which dictation waveform the app, keyboard and Live Activity draw (Settings › Dictation).
nonisolated enum DictationWaveform: String, CaseIterable, Codable, Sendable {
    case braid
    case hex
    case ribbon
    case worm

    static let key = "settings.dictationWaveform"

    var label: String {
        switch self {
        case .braid: String(localized: "Braid")
        case .hex: String(localized: "WormaBoard dots")
        case .ribbon: String(localized: "Ribbon")
        case .worm: String(localized: "Worm")
        }
    }

    static func stored(in defaults: UserDefaults?) -> DictationWaveform {
        defaults?.string(forKey: key).flatMap(DictationWaveform.init(rawValue:)) ?? .braid
    }
}

/// The chosen waveform as one still frame, for WidgetKit / Live Activity surfaces, which
/// render archived display lists rather than a running timeline.
struct HexWaveBadge: View {
    var waveform: DictationWaveform
    var width: CGFloat
    var height: CGFloat = 16
    var cooling: Bool = false

    var body: some View {
        if waveform == .hex {
            let pitch: CGFloat = width <= 30 ? 2.2 : 2.5
            HexDotMatrixBadge(
                columns: Int((width - 8) / pitch) + 1,
                rows: max(5, Int((height - 8) / pitch) + 1),
                pitch: pitch,
                cooling: cooling
            )
        } else {
            Canvas { context, size in
                WaveStrokes.draw(
                    waveform,
                    in: &context,
                    from: 1,
                    to: size.width - 1,
                    height: size.height,
                    open: cooling ? 0.35 : 0.9,
                    time: 0.55,
                    knot: cooling ? 0.5 : nil,
                    color: cooling ? HexTheme.agentBlue : HexTheme.warmPearl
                )
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
        }
    }
}

/// Static braided dot-matrix glyph for WidgetKit / Live Activity surfaces
/// where SpringBoard renders archived display lists rather than Metal drawables.
struct HexDotMatrixBadge: View {
    var columns: Int = 21
    var rows: Int = 7
    var pitch: CGFloat = 2.6
    var cooling: Bool = false

    var body: some View {
        Canvas { context, size in
            let midX = size.width * 0.5
            let midY = size.height * 0.5
            let halfRows = CGFloat(rows - 1) * 0.5
            let halfCols = CGFloat(columns - 1) * 0.5
            let tint = cooling
                ? SIMD3<Double>(0.76, 0.85, 0.98)
                : SIMD3<Double>(0.96, 0.93, 0.87)

            for i in 0..<columns {
                let xn = Double(i) / Double(max(1, columns - 1))
                let edge = sin(.pi * xn)
                let amp = (0.35 + 0.65 * sin(.pi * xn)) * Double(halfRows * 0.82)
                let yA = Double(halfRows) + amp * sin(2.0 * .pi * 1.45 * xn - 0.5)
                let yB = Double(halfRows) - amp * sin(2.0 * .pi * 1.45 * xn - 0.5)

                for j in 0..<rows {
                    let dA = abs(Double(j) - yA)
                    let dB = abs(Double(j) - yB)
                    let litA = exp(-(dA * dA) / 0.42)
                    let litB = exp(-(dB * dB) / 0.42)
                    let power = min(1.0, (1.0 - (1.0 - litA) * (1.0 - litB)) * (0.25 + 0.75 * edge))
                    let alpha = 0.07 * edge + 0.89 * pow(power, 0.9)
                    let r = (0.26 + 0.16 * pow(power, 0.6)) * Double(pitch)
                    let cx = midX + (CGFloat(i) - halfCols) * pitch
                    let cy = midY + (CGFloat(j) - halfRows) * pitch
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: tint.x, green: tint.y, blue: tint.z, opacity: alpha))
                    )
                }
            }
        }
        .frame(
            width: CGFloat(columns - 1) * pitch + 8,
            height: CGFloat(rows - 1) * pitch + 8
        )
        .accessibilityHidden(true)
    }
}

/// The stroke waveforms, after the wormadev mark's stroke (thin ends, full in the middle),
/// shared by `BraidScopeView` and `HexWaveBadge`. `.hex` is the Metal dot scope instead.
enum WaveStrokes {
    /// `open` 0...1 is how far the line swings; `knot` (0...1 along the run) is where the
    /// transcribing motion is: the braid's gathered knot, the ribbon's swell, the worm's head.
    static func draw(
        _ waveform: DictationWaveform,
        in context: inout GraphicsContext,
        from start: CGFloat,
        to end: CGFloat,
        height: CGFloat,
        open: Double,
        time: Double,
        knot: Double?,
        color: Color
    ) {
        guard end > start else { return }
        let x = { (u: Double) in start + (end - start) * u }
        let mid = height / 2
        switch waveform {
        case .braid, .hex:
            for (sign, opacity) in [(1.0, 1.0), (-1.0, 0.45)] {
                let points = (0...64).map { i -> CGPoint in
                    let u = Double(i) / 64
                    var amplitude = sin(.pi * u) * height * 0.3 * open
                    if let knot {
                        amplitude *= 0.35 + 0.65 * exp(-pow((u - knot) * 5, 2))
                    }
                    return CGPoint(x: x(u), y: mid + sign * amplitude * sin(u * .pi * 3.2 - time * 4))
                }
                context.fill(
                    tapered(points) { u in 1.5 + sin(.pi * u) * height * 0.11 },
                    with: .color(color.opacity(opacity))
                )
            }
        case .ribbon:
            let speed = knot == nil ? 5.0 : 2.5
            let points = (0...80).map { i -> CGPoint in
                let u = Double(i) / 80
                var amplitude = sin(.pi * u) * height * 0.32 * open
                if let knot {
                    amplitude *= 0.5 + 0.5 * exp(-pow((u - knot) * 6, 2))
                }
                return CGPoint(x: x(u), y: mid + amplitude * sin(u * .pi * 4 - time * speed))
            }
            let swell = knot == nil ? 0.12 + 0.1 * open : 0.1
            context.fill(
                tapered(points) { u in 2 + sin(.pi * u) * height * swell },
                with: .color(color)
            )
        case .worm:
            let length = knot == nil ? 0.42 : 0.3
            let head = knot.map { ($0 + 0.1) / 1.2 * (1 + length) } ?? 0.5 + length / 2
            let speed = knot == nil ? 6.0 : 3.0
            let points = (0...48).compactMap { i -> CGPoint? in
                let u = head - length + length * Double(i) / 48
                guard (0...1).contains(u) else { return nil }
                let amplitude = height * 0.22 * max(open, 0.15)
                return CGPoint(x: x(u), y: mid + amplitude * sin(u * .pi * 6 - time * speed))
            }
            guard points.count > 2 else { return }
            context.fill(
                tapered(points) { u in 2.5 + pow(u, 1.3) * height * 0.24 },
                with: .color(color)
            )
            if let last = points.last {
                let r = (2.5 + height * 0.24) / 2
                context.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
    }

    /// A filled outline around `points`, `width(u)` wide at each point.
    private static func tapered(_ points: [CGPoint], width: (Double) -> Double) -> Path {
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
