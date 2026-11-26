import SwiftUI

/// Manage autocorrect rules › Import: every row of the file, the ones it can't use with why,
/// conflicts with your corrections and blocks, and a switch for each rule to apply.
struct AutocorrectRulesImportView: View {
    let rows: [AutocorrectRulesFile.Row]
    let applied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var conflicts: [String: String] = [:]

    private var rules: [AutocorrectRule] { rows.compactMap { try? $0.result.get() } }
    private var rejected: Int { rows.count - rules.count }

    var body: some View {
        SettingsPageScaffold(title: "Import rules") {
            Text(rejected == 0
                ? String(localized: "\(rules.count) rules in this file.")
                : String(localized: "\(rules.count) rules in this file, \(rejected) rows can't be used."))
                .font(.system(size: 13))
                .foregroundStyle(HexTheme.textMuted)
                .padding(.horizontal, 16)

            SettingsCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, row in
                    if n > 0 { SettingsDivider() }
                    switch row.result {
                    case .success(let rule): ruleRow(rule)
                    case .failure(let rejection):
                        SettingsRowLabel(title: String(localized: "Row \(row.id + 1)"), detail: rejection.reason)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .opacity(0.6)
                    }
                }
            }

            VStack(spacing: 4) {
                OnboardingPrimaryButton(title: "Apply \(chosen.count) rules", enabled: !chosen.isEmpty, action: apply)
                OnboardingQuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.top, 8)
        }
        .onAppear(perform: load)
    }

    private func ruleRow(_ rule: AutocorrectRule) -> some View {
        let language = KeyboardLanguage(rawValue: rule.language)?.displayName ?? rule.language
        let detail = conflicts[rule.key].map { "\(language) · \($0)" } ?? language
        return SettingsToggleRow(
            title: "\(rule.typed) → \(rule.correction)",
            detail: detail,
            isOn: Binding(
                get: { chosen.contains(rule.key) },
                set: { on in
                    if on { chosen.insert(rule.key) } else { chosen.remove(rule.key) }
                }
            )
        )
    }

    private func load() {
        let store = AutocorrectRules()
        let snapshot = TypingJournal.load(from: FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)?
            .appendingPathComponent(TypingJournal.fileName))
        var learned: [String: [String: String]] = [:]
        for code in Set(rules.map(\.language)) {
            learned[code] = TypingLearning.derive(from: snapshot.corrections, language: code).typos
        }
        conflicts = Self.conflicts(rules, imported: store.imported, blocked: store.blocked, learned: learned)
        chosen = Set(rules.map(\.key)).subtracting(rules.filter { Self.isAlreadyThere($0, imported: store.imported) }.map(\.key))
    }

    private func apply() {
        let store = AutocorrectRules()
        let picked = rules.filter { chosen.contains($0.key) }
        store.importRules(picked)
        for rule in picked { store.unblock(AutocorrectBlock(typed: rule.typed, correction: rule.correction)) }
        applied()
        dismiss()
    }

    private static func isAlreadyThere(_ rule: AutocorrectRule, imported: [AutocorrectRule]) -> Bool {
        imported.contains { $0.key == rule.key && $0.correction == rule.correction }
    }

    /// What each rule (`AutocorrectRule.key`) runs into: an imported rule for the same word, a
    /// fix learned for it in that language (`learned`: language → typo → word), or a block.
    static func conflicts(
        _ rules: [AutocorrectRule], imported: [AutocorrectRule], blocked: [AutocorrectBlock], learned: [String: [String: String]]
    ) -> [String: String] {
        var out: [String: String] = [:]
        for rule in rules {
            let typed = rule.typed.lowercased()
            if blocked.contains(where: { $0.key == AutocorrectBlock(typed: rule.typed, correction: rule.correction).key }) {
                out[rule.key] = String(localized: "You blocked this; applying it unblocks it")
            } else if let existing = imported.first(where: { $0.key == rule.key }) {
                out[rule.key] = existing.correction == rule.correction
                    ? String(localized: "Already imported")
                    : String(localized: "Replaces your rule \(existing.typed) → \(existing.correction)")
            } else if let word = learned[rule.language]?[typed], word.lowercased() != rule.correction.lowercased() {
                out[rule.key] = String(localized: "WormaBoard learned \(rule.typed) → \(word); this wins")
            }
        }
        return out
    }
}
