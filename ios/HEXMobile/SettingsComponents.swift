import SwiftUI

/// The home screen's four settings pages.
enum SettingsPage: String, Hashable, CaseIterable {
    case dictation
    case keyboard
    case privacy
    case experiments

    var title: String {
        switch self {
        case .dictation: String(localized: "Dictation")
        case .keyboard: String(localized: "Keyboard")
        case .privacy: String(localized: "Privacy")
        case .experiments: String(localized: "Labs")
        }
    }

    var icon: String {
        switch self {
        case .dictation: "waveform"
        case .keyboard: "keyboard"
        case .privacy: "lock"
        case .experiments: "testtube.2"
        }
    }
}

/// A settings page: a short scrolling column of cards under an inline title.
struct SettingsPageScaffold<Content: View>: View {
    let title: LocalizedStringKey
    /// The `id` of a row to start at instead of the top.
    var startsAt: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                guard let startsAt else { return }
                DispatchQueue.main.async { proxy.scrollTo(startsAt, anchor: .top) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(SettingsSnapshotFixture.scrollsToEnd ? .bottom : .top)
        .background(HexTheme.bgDeep.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HexTheme.bgDeep, for: .navigationBar)
    }
}

/// Rows on `bgBase` with the theme's corner radius.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            HexTheme.bgBase,
            in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous)
        )
    }
}

/// A small label above a card, such as Privacy's "Advanced".
struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HexTheme.textMuted)
            .padding(.leading, 16)
            .padding(.top, 12)
    }
}

struct SettingsDivider: View {
    var leading: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(HexTheme.borderWeak)
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

/// A row's title, and its one-line description when it has one.
struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HexTheme.textBase)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(HexTheme.textMuted)
            }
        }
    }
}

/// A switch with its one-line description.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, detail: detail)
        }
        .tint(HexTheme.success)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }
}

/// A row that opens something: a page (chevron) or another app (arrow).
struct SettingsLinkLabel: View {
    let title: String
    var icon: String?
    var trailingIcon = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HexTheme.textMuted)
                    .frame(width: 22)
            }
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HexTheme.textBase)
            Spacer(minLength: 8)
            Image(systemName: trailingIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// A menu's current value with the up-down chevron.
struct SettingsMenuValue: View {
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HexTheme.textMuted)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// A small segmented control in the settings rows' style.
struct SettingsSegments<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let label: KeyPath<Item, String>
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selected
                Button {
                    onSelect(item)
                } label: {
                    Text(item[keyPath: label])
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(isSelected ? HexTheme.textBase : HexTheme.textMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            isSelected ? Color.white.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(2)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

/// Simulator scenes for the home screen and its pages (`--snap-state <name>`):
///
/// - `settings-home`: home, everything ready. `setup`: home, keyboard added but Full Access
///   not confirmed yet. `setup-sheet`: the same, with the setup sheet open;
///   `setup-sheet-microphone`: the sheet before iOS has asked for the microphone.
///   A scene with `-noaccess` (`setup-sheet-noaccess`, `settings-keyboard-noaccess`) has the
///   keyboard report Full Access off.
/// - `settings-<page>` opens a page (`dictation`, `keyboard`, `privacy`, `experiments`) with
///   every switch at its default; `-on` turns the switches on, `-end` starts scrolled to the end.
///   `settings-keyboard-languages[-on]` opens Keyboard › Languages.
///   `settings-privacy-confirm` opens Record typing logs' consent dialog.
///   `settings-privacy-on-rules` has Labs › Manage autocorrect rules on with learned fixes,
///   rules and a block; `-sheet`, `-import` or `-export` after it opens Autocorrect rules there.
///
/// `KeyboardSetupMonitor.refresh` and `DictationController` supply the matching state.
enum SettingsSnapshotFixture {
    static let scene: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--snap-state"), idx + 1 < args.count else { return nil }
        let value = args[idx + 1]
        return value.hasPrefix("settings-") || value.hasPrefix("setup-sheet") ? value : nil
    }()

    static var initialPath: [SettingsPage] {
        guard let scene else { return [] }
        let name = scene.dropFirst("settings-".count).split(separator: "-").first.map(String.init)
        return name.flatMap(SettingsPage.init(rawValue:)).map { [$0] } ?? []
    }

    static var showsSetupSheet: Bool {
        scene?.hasPrefix("setup-sheet") == true
    }

    /// `settings-privacy-confirm`: Record typing logs' consent dialog, open.
    static var confirmsTypingLogs: Bool {
        scene?.hasSuffix("-confirm") == true
    }

    static var scrollsToEnd: Bool {
        scene?.hasSuffix("-end") == true
    }

    enum AutocorrectRulesScreen { case main, importing, export }

    /// `settings-privacy-on-rules-<sheet|import|export>`: which Autocorrect rules screen is open.
    static var autocorrectRulesScreen: AutocorrectRulesScreen? {
        guard let scene, scene.contains("-rules-") else { return nil }
        if scene.hasSuffix("-import") { return .importing }
        return scene.hasSuffix("-export") ? .export : .main
    }

    /// The import preview's rows for `-rules-import`: one of each conflict and rejection.
    static var autocorrectRulesImportRows: [AutocorrectRulesFile.Row]? {
        guard autocorrectRulesScreen == .importing else { return nil }
        let csv = "language,typed,correction,count\nen,adn,and,5\nde,udn,und,3\nen,wrok,wrong,2\nen,Figmaly,Figma,1\nen,teh,teh,1\nxx,foo,bar,1\n"
        return try? AutocorrectRulesFile.parse(Data(csv.utf8)).get()
    }

    /// `-rules` scenes: learned fixes, an imported rule and a block, as a phone that used them has.
    @MainActor
    private static func seedAutocorrectRules() {
        let rules = AutocorrectRules()
        rules.imported = [AutocorrectRule(language: "de", typed: "udn", correction: "und", count: 3)]
        rules.blocked = [AutocorrectBlock(typed: "Figmaly", correction: "Figma")]
        let pairs: [(TypingJournalCorrection.Kind, String, String, String, Int)] = [
            (.autocorrected, "teh", "the", "en", 4), (.retyped, "recieve", "receive", "en", 3),
            (.retyped, "wrok", "work", "en", 2), (.picked, "nciht", "nicht", "de", 2),
        ]
        var snapshot = TypingJournalSnapshot()
        for (kind, typed, final, language, count) in pairs {
            for _ in 0..<count {
                snapshot.corrections.append(TypingJournalCorrection(kind: kind, typed: typed, final: final, at: 0, language: language))
            }
        }
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)?
            .appendingPathComponent(TypingJournal.fileName),
            let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// `settings-experiments-on`: Adaptive touch partway through learning, as a keyboard with
    /// Full Access reports it.
    static var adaptiveTouchStatus: AdaptiveTouchStatus? {
        guard let scene, scene.hasPrefix("settings-experiments") else { return nil }
        return scene.contains("-on") ? .learning(taps: 240) : nil
    }

    /// `settings-keyboard-languages[-on]`: Keyboard › Languages, open (Automatic, or with
    /// `-on` English on QWERTZ, Français and Русский with Switch dictation too).
    static var opensKeyboardLanguages: Bool {
        scene?.hasPrefix("settings-keyboard-languages") == true
    }

    /// Writes the page's switches to the App Group so every run renders the same.
    @MainActor
    static func applyDefaults() {
        guard let scene, scene.hasPrefix("settings-") else { return }
        let on = scene.contains("-on")
        let keyboard = FullKeyboardSettings()
        keyboard.isEnabled = on || opensKeyboardLanguages
        keyboard.autoCapitalization = true
        // `--hex-key left` renders the page with the Hex key on the left.
        let args = ProcessInfo.processInfo.arguments
        keyboard.hexKeyOnLeft = args.firstIndex(of: FullKeyboardSettings.hexKeyLaunchArgument)
            .flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } == "left"
        keyboard.numberRow = on
        keyboard.autocorrect = true
        keyboard.spatialAutocorrect = true
        keyboard.germanSpatialAutocorrect = on
        keyboard.koreanKeyboard = on
        keyboard.arabicKeyboard = on
        keyboard.dvorakPunctuation = on
        keyboard.clipboardHistory = on
        keyboard.symbolHolds = on
        keyboard.domainHolds = on
        keyboard.manageAutocorrectRules = on
        if scene.contains("-rules") { seedAutocorrectRules() }
        keyboard.commaPeriodKeys = on
        keyboard.quickAccents = on
        keyboard.emojiShortcodes = on
        keyboard.emojiLettersUnderEmojiKey = on
        GifSearchSettings().isEnabled = on
        keyboard.keyboardThemesEnabled = false
        keyboard.keyboardTheme = .automatic
        keyboard.suggestSwearWords = on
        keyboard.keyPopups = true
        keyboard.haptics = true
        keyboard.emojiKey = true
        keyboard.emojiSuggestions = true
        keyboard.swipeTyping = true
        keyboard.swipeMoreLanguages = on
        let emojiUsage = EmojiUsageStore()
        emojiUsage.clear()
        if on {
            emojiUsage.record("🎉")
        }
        LanguageSettings().keyboardLanguages = on ? [.english, .french, .russian] : []
        LanguageSettings().setLetterLayout(on ? .qwertz : .qwerty, for: .english)
        LanguageSettings().setLetterLayout(.azerty, for: .french)
        LanguageSettings().currentKeyboardLanguage = nil
        LanguageSettings().dictationFollowsKeyboard = on
        CleanupTaggerSettings().isEnabled = on
        AppleIntelligenceCleanupSettings().isEnabled = false
        CustomVocabularySettings().isEnabled = on
        CustomVocabularySettings().terms = on ? ["OpenCode", "SwiftUI", "TestFlight"] : []
        DictationTranslationSettings().isEnabled = on
        LiveDictationSettings().showsPreview = true
        LiveDictationSettings().typesIntoField = on
        DictationTranslationSettings().targetLanguage = "ja"
        TypingJournalSettings().isEnabled = on
        TypingJournalSettings().learnsPerLanguage = on
        TypingLogSettings().isEnabled = on
        HinglishSettings().isEnabled = on
        GreeklishSettings().isEnabled = on
        TwoLanguageDictationSettings().isEnabled = on
        VoiceIsolationSettings().isEnabled = on
        AdaptiveTouchSettings().isEnabled = on
        // Settings scenes skip preparing a model, so this only draws the switch.
        MultilingualParakeetSettings().isEnabled = on || scene.contains("-multilingual-")
    }
}
