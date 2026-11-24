import Foundation

/// The dictation indicator's stage (`BraidScopeView`).
enum DotScopePhase: Equatable, Sendable {
    case hidden
    case idle
    case starting
    case recording
    case processing
    case failed
}

/// Loudness helpers the indicator's callers share (dBFS).
nonisolated enum DotScopeSimulation {
    /// A voice-like loudness over time, for simulator fixtures.
    static func demoLoudness(at time: Float) -> Float {
        let tau: Float = 2.0 * .pi
        let phraseDur: Float = 2.4
        let spokenDur: Float = 1.7
        let phrase = floor(time / phraseDur)
        let t = time - phrase * phraseDur
        let level: Float
        if t > spokenDur {
            level = 0.04
        } else {
            let shape = pow(max(0.0, sin(.pi * t / spokenDur)), 0.4)
            let rate = tau * (4.3 + 0.6 * sin(phrase * 1.7))
            let syllable = 0.5 + 0.5 * sin(rate * t + phrase)
            let stress = 0.75 + 0.25 * sin(tau * 1.1 * t + 2.0 * phrase)
            level = min(1.0, max(0.0, 0.08 + 0.82 * shape * pow(syllable, 1.6) * stress))
        }
        return -58.0 + 28.0 * level
    }

    static func loudness(fromNormalized level: Float) -> Float {
        let clamped = min(1.0, max(0.0, level))
        return clamped <= 0.001 ? -90.0 : (-54.0 + 34.0 * clamped)
    }
}
