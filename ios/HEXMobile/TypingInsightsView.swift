import SwiftUI

/// What Learn how I type has gathered so far, with a way to erase it.
struct TypingInsightsView: View {
    @State private var snapshot = TypingJournalSnapshot()
    @State private var disabledFixes: Set<String> = []
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(HexTheme.textMuted)

            if !dictationFixes.isEmpty {
                section("Dictation fixes WormaBoard learned") {
                    ForEach(dictationFixes) { fix in
                        Toggle(isOn: isApplied(fix)) {
                            HStack {
                                Text("\(fix.heard) → \(fix.meant)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(HexTheme.textBase)
                                Spacer()
                                Text("\(fix.count)×")
                                    .font(.system(size: 12))
                                    .foregroundStyle(HexTheme.textMuted)
                            }
                        }
                        .tint(HexTheme.success)
                    }
                }
            }

            if !snapshot.dictationOutcomes.isEmpty {
                section("Dictation") {
                    row(String(localized: "Kept as is"), detail: share(of: .kept))
                    row(String(localized: "Edited"), detail: share(of: .edited))
                }
            }

            if !topFixes.isEmpty {
                section("Words you fix most") {
                    ForEach(topFixes, id: \.label) { fix in
                        if managesRules {
                            HStack(spacing: 10) {
                                row(fix.label, detail: "\(fix.count)×")
                                fixMenu(typed: fix.typed, final: fix.final)
                            }
                        } else {
                            row(fix.label, detail: "\(fix.count)×")
                        }
                    }
                }
            }

            if !missedKeys.isEmpty {
                section("Where you tap off-center") {
                    ForEach(missedKeys, id: \.key) { item in
                        row(item.key.uppercased(), detail: item.direction)
                    }
                }
            }

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("Delete what WormaBoard learned")
                    .font(.system(size: 13, weight: .medium))
            }
            .disabled(snapshot.isEmpty && disabledFixes.isEmpty && !hasTypingConfigs)
            .confirmationDialog("Delete what WormaBoard learned?", isPresented: $confirmingDelete, titleVisibility: hasTypingConfigs ? .visible : .automatic) {
                Button("Delete", role: .destructive) {
                    TypingJournal.delete()
                    AdaptiveTouchSettings().requestReset()
                    // Typing configs hold your words too, so they go with it.
                    if hasTypingConfigs {
                        let history = TypingConfigHistory()
                        TypingConfigActivation.useDefaults(history: history)
                        history.deleteAll()
                        TypingConfigHealth().deleteAll()
                        TypingConfigStartupGuard().clearFallback()
                    }
                    reload()
                }
            } message: {
                if hasTypingConfigs {
                    Text("This also deletes your typing configs, which hold your words, and the keyboard goes back to WormaBoard defaults.")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private var summary: String {
        if snapshot.isEmpty {
            return String(localized: "Nothing learned yet")
        }
        let taps = snapshot.tapCount
        let fixes = snapshot.corrections.filter(\.teaches).count
        let dictations = snapshot.dictationOutcomes.count
        return dictations == 1
            ? String(localized: "\(taps) taps, \(fixes) typing fixes and 1 dictation learned")
            : String(localized: "\(taps) taps, \(fixes) typing fixes and \(dictations) dictations learned")
    }

    /// Learned fixes, most used first; each can be switched off. With Learn each language
    /// separately on, every language's are listed, so a fix only one language learned shows too.
    private var dictationFixes: [DictationLearnedFix] {
        let learned = TypingJournalSettings().learnsPerLanguage
            ? snapshot.learnedDictationFixesByLanguage()
            : snapshot.learnedDictationFixes
        return Array(learned
            .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
            .prefix(12))
    }

    private func isApplied(_ fix: DictationLearnedFix) -> Binding<Bool> {
        Binding(
            get: { !disabledFixes.contains(fix.id) },
            set: { applied in
                if applied {
                    disabledFixes.remove(fix.id)
                } else {
                    disabledFixes.insert(fix.id)
                }
                TypingJournalSettings().disabledDictationFixes = disabledFixes
            }
        )
    }

    private func share(of outcome: DictationOutcome) -> String {
        let total = snapshot.dictationOutcomes.count
        guard total > 0 else { return "–" }
        let percent = (Double(snapshot.count(of: outcome)) / Double(total) * 100).rounded()
        return "\(Int(percent))%"
    }

    private var topFixes: [(label: String, typed: String, final: String, count: Int)] {
        var counts: [String: (typed: String, final: String, count: Int)] = [:]
        for correction in snapshot.corrections where correction.kind != .undone && correction.kind != .keptTyped && correction.teaches {
            counts["\(correction.typed) → \(correction.final)", default: (correction.typed, correction.final, 0)].count += 1
        }
        return counts.sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
            .prefix(5)
            .map { (label: $0.key, typed: $0.value.typed, final: $0.value.final, count: $0.value.count) }
    }

    /// Labs › Manage autocorrect rules: forget one learned pair, or also never make it again.
    private func fixMenu(typed: String, final: String) -> some View {
        Menu {
            Button("Forget this correction") {
                TypingJournal.forget(typed: typed, final: final)
                reload()
            }
            Button("Never change \(typed) to \(final)", role: .destructive) {
                AutocorrectRules().block(AutocorrectBlock(typed: typed, correction: final))
                TypingJournal.forget(typed: typed, final: final)
                reload()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HexTheme.textMuted)
                .frame(width: 26, height: 26)
                .background(HexTheme.layer02, in: Circle())
        }
        .accessibilityLabel("Manage \(typed) → \(final)")
    }

    private var missedKeys: [(key: String, direction: String)] {
        snapshot.keys
            .filter { $0.value.count >= 20 }
            .map { (key: $0.key, offset: $0.value.meanOffset) }
            .filter { hypot($0.offset.dx, $0.offset.dy) >= 0.12 }
            .sorted { hypot($0.offset.dx, $0.offset.dy) > hypot($1.offset.dx, $1.offset.dy) }
            .prefix(4)
            .map { item in
                let right = abs(item.offset.dx) < 0.08 ? nil : item.offset.dx > 0
                let low = abs(item.offset.dy) < 0.08 ? nil : item.offset.dy > 0
                return (key: item.key, direction: Self.direction(low: low, right: right))
            }
    }

    /// "low and right": where taps land from the key's centre, empty when they're centred.
    private static func direction(low: Bool?, right: Bool?) -> String {
        switch (low, right) {
        case (true?, true?): String(localized: "low and right")
        case (true?, false?): String(localized: "low and left")
        case (false?, true?): String(localized: "high and right")
        case (false?, false?): String(localized: "high and left")
        case (true?, nil): String(localized: "low")
        case (false?, nil): String(localized: "high")
        case (nil, true?): String(localized: "right")
        case (nil, false?): String(localized: "left")
        case (nil, nil): ""
        }
    }

    @State private var hasTypingConfigs = false
    @State private var managesRules = false

    private func reload() {
        hasTypingConfigs = !TypingConfigHistory().entries.isEmpty
        managesRules = FullKeyboardSettings().manageAutocorrectRules
        snapshot = TypingJournal.load(from: FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)?
            .appendingPathComponent(TypingJournal.fileName))
        disabledFixes = TypingJournalSettings().disabledDictationFixes
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
            content()
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(HexTheme.textBase)
            Spacer()
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(HexTheme.textMuted)
        }
    }
}
