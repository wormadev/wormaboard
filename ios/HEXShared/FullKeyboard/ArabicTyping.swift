import Foundation

/// Settings › Labs › Arabic keyboard, read where the pure language helpers need it
/// before a keyboard exists (Settings' Languages list, Automatic). Stored as
/// `experiments.arabicKeyboard`, off by default like every experiment.
nonisolated enum ArabicKeyboardExperiment {
    static let key = "experiments.arabicKeyboard"

    static var isEnabled: Bool {
        UserDefaults(suiteName: KeyboardBridge.appGroup)?.bool(forKey: key) ?? false
    }

    /// The flag in a store a caller already owns (LanguageSettings' injected defaults), so a
    /// test's own suite decides without touching the App Group.
    static func isEnabled(in defaults: UserDefaults?) -> Bool {
        guard let defaults else { return isEnabled }
        return defaults.object(forKey: key) as? Bool ?? false
    }
}

/// Apple's iPhone Arabic keyboard, read on the iOS 26.4 simulator (black box: Settings ›
/// Keyboards › Arabic, its keys' labels and frames from the accessibility tree). The letters
/// sit left to right as the keycaps do, ض at the left edge; text goes right to left in the
/// field, which the host lays out, so the keys insert in typing order like any other layout.
/// Row 3 has no shift (Arabic has no case): nine letters from the left edge, then delete.
/// Long presses are Apple's (`TextInput_ar.bundle/Keyboard-ar.plist`, the same runtime).
nonisolated enum ArabicTyping {
    static let letterRows = ["ضصثقفغعهخحج", "شسيبلاتنمكة", "ءظطذدزروى"]

    /// Apple's "Arabic – PC" (iOS 27.0 simulator, black box: its keys' labels and frames from the
    /// accessibility tree): ten keys a column wide in rows 1 and 2, nine letters from the left
    /// edge in row 3 and a delete key as wide as one. ء ى ئ ؤ have no key; the held keys of
    /// `letterHolds` give them, as on the Arabic layout (Apple's own PC holds unmeasured).
    static let pcLetterRows = ["ضصقفغعهخحج", "شسيبلاتنمك", "ظطذدزروةث"]

    /// The 123 and #+= pages: Arabic-Indic digits (the Western ones held under them), ؛ for ;,
    /// and the Arabic comma and question mark on 123's punctuation row; #+= keeps Western , and ?.
    static func characterRows(_ layer: KeyboardLayer, letters: KeyboardLetterLayout = .own) -> [[String]] {
        switch layer {
        case .letters: (letters == .arabicPC ? pcLetterRows : letterRows).map { $0.map(String.init) }
        case .numbers: [
            "١٢٣٤٥٦٧٨٩٠".map(String.init),
            ["-", "/", ":", "؛", "(", ")", "$", "&", "@", "\""],
            [".", "،", "؟", "!", "'"],
        ]
        case .symbols: [
            ["[", "]", "{", "}", "#", "٪", "^", "*", "+", "="],
            ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
            [".", ",", "?", "!", "'"],
        ]
        }
    }

    /// The plist's options, base first and then outward from it (the plist lists them toward
    /// the base). Apple's tashkeel key has no place on Hex's bottom row, so the harakat aren't
    /// offered.
    static let letterHolds: [String: [String]] = [
        "ا": ["ا", "ء", "آ", "إ", "أ"],
        "ء": ["ء", "ؤ", "ئ", "إ", "أ"],
        "ي": ["ي", "ئ", "ى"],
        "ى": ["ى", "ئ"],
        "و": ["و", "ؤ"],
        "ه": ["ه", "هـ"],
        "ل": ["ل", "لا"],
        "ك": ["ك", "گ"],
        "ف": ["ف", "ڤ"],
        "ز": ["ز", "ژ"],
        "ج": ["ج", "چ"],
        "ب": ["ب", "پ"],
    ]

    static let symbolHolds: [String: [String]] = {
        var holds: [String: [String]] = [
            "،": ["،", "٫", ","],
            "؟": ["؟", "?", "¿"],
            "؛": ["؛", ";"],
            "٪": ["٪", "%", "؉"],
            "$": ["$", "﷼", "€", "£", "¥", "₽"],
        ]
        for (arabic, western) in zip("١٢٣٤٥٦٧٨٩٠", "1234567890") {
            holds[String(arabic)] = [String(arabic), String(western)]
        }
        return holds
    }()

    /// Marks that end a word or clause like their Latin twins: comma, semicolon, question mark.
    static let punctuation: Set<Character> = ["،", "؛", "؟"]

    /// `word` as the typing model spells it: without tashkeel (U+064B-U+065F), the superscript
    /// alef (U+0670) or tatweel (U+0640), which the model's builder drops too. Hamza forms, ة and
    /// ى stay: they are other letters, not marks.
    static func lookupForm(_ word: String) -> String {
        String(String.UnicodeScalarView(word.unicodeScalars.filter {
            !(0x064B...0x065F).contains($0.value) && $0.value != 0x0670 && $0.value != 0x0640
        }))
    }
}
