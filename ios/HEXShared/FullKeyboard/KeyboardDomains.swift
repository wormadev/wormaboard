import Foundation

/// The domains a held `.` offers in web search and email fields with Settings › Labs ›
/// Domains on held period, as Apple's keyboard's: each locale's `UI-TopLevelDomain` in
/// `TextInput_<language>.bundle/Keyboard-<locale>.plist` (iOS 27.0 simulator runtime, 24A434),
/// first the one preselected over the key (upstream issue #2811).
nonisolated enum KeyboardDomains {
    private static let apple: [String: String] = [
        "en_US": ".com .net .edu .org .us", "en_GB": ".co.uk .com .ie .org .edu .eu .uk",
        "en_AU": ".com .au .org .edu", "en_CA": ".com .ca .org .edu", "en_IE": ".com .ie .org .edu",
        "en_IN": ".com .in .org .net", "en_NZ": ".com .co.nz .nz .org .ac", "en_SG": ".com .sg .org .net",
        "en_ZA": ".com .za .org .net", "en_JP": ".jp .co.jp .com .net", "en_PH": ".com .net .ph",
        "en_HK": ".com .tw .hk .net .中國 .台灣 .香港", "en_BD": ".com .bd .org .net",
        "en_RW": ".com .rw .org .net", "en_SA": ".com .sa .org .edu",
        "nb": ".no .com .org .edu", "sv": ".se .com .nu .org", "sv_FI": ".com .fi .net .org .info .mobi .eu",
        "es_ES": ".com .es .org .edu .eu", "es_MX": ".com .mx .org .edu .gob", "es_US": ".com .us .org .edu .gob",
        "es_AR": ".com .ar .org .edu", "es_BO": ".com .bo .org .edu", "es_BR": ".com .br .org .edu",
        "es_BZ": ".com .bz .org .edu", "es_CL": ".com .cl .org .edu", "es_CO": ".com .co .org .edu",
        "es_CR": ".com .cr .org .edu", "es_CU": ".com .cu .org .edu", "es_DO": ".com .do .org .edu",
        "es_EC": ".com .ec .org .edu", "es_GT": ".com .gt .org .edu", "es_HN": ".com .hn .org .edu",
        "es_NI": ".com .ni .org .edu", "es_PA": ".com .pa .org .edu", "es_PE": ".com .pe .org .edu",
        "es_PR": ".com .pr .org .edu", "es_PY": ".com .py .org .edu", "es_SV": ".com .sv .org .edu",
        "es_UY": ".com .uy .org .edu", "es_VE": ".com .ve .org .edu",
        "de": ".de .com .org .edu .eu", "de_AT": ".de .at .com .org .edu .eu", "de_CH": ".com .ch .org .edu .eu",
        "it": ".it .com .org .edu .eu",
        "fr_FR": ".fr .com .org .edu .eu", "fr_BE": ".fr .be .com .org .edu .eu",
        "fr_CA": ".com .ca .org .edu", "fr_CH": ".com .ch .org .edu",
        "pt_BR": ".com .br .org .edu", "pt_PT": ".com .pt .org .edu .eu",
        "pl": ".com .pl .org .edu .eu", "cs": ".cz .com .org .edu .net", "sk": ".com .sk .org .edu .net .eu",
        "hu": ".com .hu .org .edu .net .eu", "nl": ".com .nl .be .org .edu", "nl_BE": ".com .be .nl .org .edu .eu",
        "ro": ".com .ro .org .edu .net .eu", "ru": ".com .рф .ru .org .edu", "uk": ".com .укр .ua .org .edu",
        "el": ".com .ελ .gr .org .ευ .eu", "sr_Latn": ".com .rs .срб .net .edu .org",
        "ko": ".com .net .kr .co.kr .ac.kr .한국",
    ]
    /// `TextInput.framework/Keyboard-default.plist`'s, for a locale with none of its own.
    private static let fallback = ".com .org .edu .net"

    /// The keyboard's: Apple's for its language in the iPhone's region (English in the UK:
    /// `.co.uk` first) unless the language names its own (fr-CA), else in its usual region,
    /// else Apple's default.
    static func domains(for language: KeyboardLanguage, region: String?) -> [String] {
        let own = language.rawValue.replacingOccurrences(of: "-", with: "_")
        let regional = language.rawValue.contains("-") ? nil : region.map { "\(own)_\($0)" }
        let usual = language.inputModeLanguage.replacingOccurrences(of: "-", with: "_")
        let list = [regional, usual, own].lazy.compactMap { $0.flatMap { apple[$0] } }.first ?? fallback
        return list.split(separator: " ").map(String.init)
    }
}
