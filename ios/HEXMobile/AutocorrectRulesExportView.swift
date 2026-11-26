import SwiftUI

/// Manage autocorrect rules › Export: the correction pairs Learn how I type kept, with counts,
/// each one chosen or not, and the exact file to review before the share sheet opens.
struct AutocorrectRulesExportView: View {
    @State private var pairs: [AutocorrectRule] = []
    @State private var chosen: Set<String> = []
    @State private var format = AutocorrectRulesFile.Format.json
    @State private var failure: String?

    private var picked: [AutocorrectRule] { pairs.filter { chosen.contains(Self.id($0)) } }

    var body: some View {
        SettingsPageScaffold(title: "Export corrections") {
            Text("Only the pairs you choose, their counts and language. Never the text around them.")
                .font(.system(size: 13))
                .foregroundStyle(HexTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            SettingsSectionHeader(title: "Corrections")
            SettingsCard {
                if pairs.isEmpty {
                    Text("No corrections learned yet")
                        .font(.system(size: 15))
                        .foregroundStyle(HexTheme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                ForEach(Array(pairs.enumerated()), id: \.element) { n, pair in
                    if n > 0 { SettingsDivider() }
                    SettingsToggleRow(
                        title: "\(pair.typed) → \(pair.correction)",
                        detail: "\(KeyboardLanguage(rawValue: pair.language)?.displayName ?? pair.language) · \(pair.count)×",
                        isOn: Binding(
                            get: { chosen.contains(Self.id(pair)) },
                            set: { on in
                                if on { chosen.insert(Self.id(pair)) } else { chosen.remove(Self.id(pair)) }
                            }
                        )
                    )
                }
            }

            HStack {
                SettingsSectionHeader(title: "Review")
                Spacer()
                SettingsSegments(items: AutocorrectRulesFile.Format.allCases, selected: format, label: \.label) { format = $0 }
                    .padding(.top, 12)
            }
            Text(AutocorrectRulesFile.export(picked, as: format))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HexTheme.textBase)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(HexTheme.bgBase, in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous))

            if let failure {
                Text(failure)
                    .font(.system(size: 13))
                    .foregroundStyle(HexTheme.danger)
                    .padding(.horizontal, 16)
            }

            OnboardingPrimaryButton(title: "Share \(picked.count) corrections", enabled: !picked.isEmpty, action: share)
                .padding(.top, 8)
        }
        .onAppear(perform: load)
    }

    private static func id(_ pair: AutocorrectRule) -> String { pair.key + "\t" + pair.correction }

    private func load() {
        let snapshot = TypingJournal.load(from: FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)?
            .appendingPathComponent(TypingJournal.fileName))
        let fallback = (LanguageSettings().keyboardLanguages.first ?? .english).rawValue
        pairs = Self.pairs(from: snapshot.corrections, fallbackLanguage: fallback)
        chosen = Set(pairs.map(Self.id))
    }

    /// "Words you fix most"'s pairs, every one, per language and with counts; a correction
    /// recorded before corrections carried a language goes under `fallbackLanguage`.
    static func pairs(from corrections: [TypingJournalCorrection], fallbackLanguage: String) -> [AutocorrectRule] {
        var counts: [AutocorrectRule: Int] = [:]
        for correction in corrections where correction.kind != .undone && correction.kind != .keptTyped && correction.teaches {
            let pair = AutocorrectRule(
                language: correction.language ?? fallbackLanguage, typed: correction.typed, correction: correction.final, count: 0
            )
            counts[pair, default: 0] += 1
        }
        return counts
            .map { pair, count in AutocorrectRule(language: pair.language, typed: pair.typed, correction: pair.correction, count: count) }
            .sorted { ($1.count, $0.typed, $0.language) < ($0.count, $1.typed, $1.language) }
    }

    private func share() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutocorrectRulesExport-" + UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("autocorrect-rules.\(format.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(AutocorrectRulesFile.export(picked, as: format).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            failure = String(localized: "WormaBoard couldn’t write the file.")
            return
        }
        ShareSheet.present([url]) { _ in
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

private extension AutocorrectRulesFile.Format {
    var label: String { rawValue.uppercased() }
}
