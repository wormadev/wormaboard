import Foundation

@MainActor
extension FullKeyboardEngine {
    /// Hands what the journal learned (typos, rejected corrections) to autocorrect, with Labs ›
    /// Manage autocorrect rules' imported rules and blocks on top; nothing learned while Learn
    /// how I type is off.
    func syncLearning() {
        let language = autocorrect.language, partner = autocorrect.partner?.language
        autocorrect.applyLearning(
            withTypingConfig(journal?.typingLearning(for: language) ?? TypingLearning()).adding(autocorrectRules, language: language),
            partner: withTypingConfig(journal?.typingLearning(for: partner) ?? TypingLearning()).adding(autocorrectRules, language: partner)
        )
    }
}
