import Foundation

/// One autocorrect fix: `typed` becomes `correction` on space in `language`
/// (`KeyboardLanguage.rawValue`). `count` is how often it was made, carried through export
/// and import only.
nonisolated struct AutocorrectRule: Hashable, Sendable {
    var language: String
    var typed: String
    var correction: String
    var count: Int

    /// Rules match whatever case they were typed in, so one per language and typed word.
    var key: String { language + "\t" + typed.lowercased() }
}

/// A replacement autocorrect may never make, in any language: `typed` stays as typed instead
/// of becoming `correction`.
nonisolated struct AutocorrectBlock: Hashable, Sendable {
    var typed: String
    var correction: String

    var key: String { typed.lowercased() + "\t" + correction.lowercased() }
}

/// Settings › Labs › Manage autocorrect rules: the rules you imported and the replacements you
/// blocked, in the App Group so the keyboard reads them. Kept while the experiment is off, but
/// applied only while it's on (`TypingLearning.adding(_:language:)`).
@MainActor
struct AutocorrectRules {
    private enum Key {
        static let imported = "autocorrectRules.imported"
        static let blocked = "autocorrectRules.blocked"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var isEnabled: Bool { FullKeyboardSettings(defaults: defaults).manageAutocorrectRules }

    var imported: [AutocorrectRule] {
        get {
            (defaults?.stringArray(forKey: Key.imported) ?? []).compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 4, let count = Int(parts[3]) else { return nil }
                return AutocorrectRule(language: parts[0], typed: parts[1], correction: parts[2], count: count)
            }
        }
        nonmutating set {
            defaults?.set(newValue.map { "\($0.language)\t\($0.typed)\t\($0.correction)\t\($0.count)" }, forKey: Key.imported)
        }
    }

    var blocked: [AutocorrectBlock] {
        get {
            (defaults?.stringArray(forKey: Key.blocked) ?? []).compactMap { line in
                let parts = line.components(separatedBy: "\t")
                return parts.count == 2 ? AutocorrectBlock(typed: parts[0], correction: parts[1]) : nil
            }
        }
        nonmutating set { defaults?.set(newValue.map { "\($0.typed)\t\($0.correction)" }, forKey: Key.blocked) }
    }

    /// Adds `rules`, each replacing an imported rule for the same language and word.
    func importRules(_ rules: [AutocorrectRule]) {
        let keys = Set(rules.map(\.key))
        imported = imported.filter { !keys.contains($0.key) } + rules
    }

    func remove(_ rule: AutocorrectRule) {
        imported = imported.filter { $0.key != rule.key }
    }

    func block(_ block: AutocorrectBlock) {
        guard !blocked.contains(where: { $0.key == block.key }) else { return }
        blocked = blocked + [block]
    }

    func unblock(_ block: AutocorrectBlock) {
        blocked = blocked.filter { $0.key != block.key }
    }
}

extension TypingLearning {
    /// This learning with your imported rules for `language` and your blocks on top, in memory
    /// only; unchanged while Manage autocorrect rules is off. An imported rule wins over a fix
    /// learned for the same word and over having kept that word; a block wins over both.
    @MainActor
    func adding(_ rules: AutocorrectRules, language: KeyboardLanguage?) -> TypingLearning {
        guard rules.isEnabled else { return self }
        var out = self
        for rule in rules.imported where rule.language == language?.rawValue {
            let typed = rule.typed.lowercased()
            out.typos[typed] = rule.correction
            out.rejected.remove(typed)
        }
        out.blockedFixes = Set(rules.blocked.map(\.key))
        out.typos = out.typos.filter { !out.blocks($0.key, to: $0.value) }
        return out
    }

    /// Whether you blocked autocorrect from putting `fix` in place of `typed`, in any case.
    func blocks(_ typed: String, to fix: String) -> Bool {
        !blockedFixes.isEmpty && blockedFixes.contains(AutocorrectBlock(typed: typed, correction: fix).key)
    }
}
