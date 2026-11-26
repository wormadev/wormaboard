import UIKit
import XCTest
@testable import HEX

/// Settings › Labs › Symbols on held keys and Domains on held period: off by default, holding
/// what every key held before; on, a held letter offers its symbol (preselected), a held `.` a
/// row of punctuation, and in web search and email fields the keyboard's domains instead.
extension FullKeyboardEngineTests {
    func testHeldExtrasAreOffByDefault() {
        let settings = FullKeyboardSettings(defaults: defaults)
        XCTAssertFalse(settings.symbolHolds, "off by default")
        XCTAssertFalse(settings.domainHolds, "off by default")
        XCTAssertFalse(FullKeyboardSettings(defaults: nil).symbolHolds, "without the App Group")
        XCTAssertFalse(FullKeyboardSettings(defaults: nil).domainHolds, "without the App Group")
        settings.applyLaunchArguments(["HEX", FullKeyboardSettings.symbolHoldsLaunchArgument, FullKeyboardSettings.domainHoldsLaunchArgument])
        XCTAssertEqual(defaults.object(forKey: "experiments.symbolHolds") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "experiments.domainHolds") as? Bool, true)

        XCTAssertEqual(engine.heldExtras, HeldKeyExtras())
        down(1, .character("q"))
        XCTAssertFalse(engine.openAccentMenuIfEligible(forTouch: 1), "off: q holds nothing, as before")
        up(1, .character("q"))
        XCTAssertNil(engine.heldHint(for: engine.layout.key(.character("a"))!))
        down(2, .character("e"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 2))
        XCTAssertEqual(engine.activeAccentMenu?.options.contains("|"), false)
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, "e")
    }

    func testLetterSymbolMapMatchesAndroid() {
        let rows = ["qwertyuiop": "%\\|=[]<>{}", "asdfghjkl": "@#$_&-+()", "zxcvbnm": "*\"':;!?"]
        for (letters, symbols) in rows {
            for (letter, symbol) in zip(letters, symbols) {
                XCTAssertEqual(AccentCatalog.letterSymbol(for: String(letter), topRow: letters.hasPrefix("q")), String(symbol), "\(letter)")
            }
        }
        XCTAssertNil(AccentCatalog.letterSymbol(for: "y", topRow: false), "QWERTZ's y on row 3 has none")
        XCTAssertEqual(AccentCatalog.letterSymbol(for: "a", topRow: true), "@", "AZERTY's a keeps its own")
        XCTAssertNil(AccentCatalog.letterSymbol(for: "ж", topRow: false))
        XCTAssertEqual(AccentCatalog.letterSymbol(for: "M", topRow: false), "?")
    }

    func testHeldLetterOffersItsSymbolFirstAndTypesItOnRelease() {
        engine.heldExtras = HeldKeyExtras(symbols: true)
        down(1, .character("q"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        XCTAssertEqual(Set(engine.activeAccentMenu?.options ?? []), ["q", "%"])
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, "%")
        up(1, .character("q"))
        XCTAssertEqual(target.text, "%")
        XCTAssertEqual(engine.heldHint(for: engine.layout.key(.character("q"))!), "%")

        // A letter with accents keeps Apple's arrangement, the symbol beside the key's own.
        down(2, .character("e"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 2))
        let menu = try! XCTUnwrap(engine.activeAccentMenu)
        XCTAssertEqual(menu.options, ["ë", "é", "e", "|", "è", "ê", "ě", "ẽ", "ē", "ė", "ę"])
        XCTAssertEqual(menu.selectedOption, "|")
        up(2, .character("e"))
        XCTAssertEqual(target.text, "%|")

        // Quick accents still opens on the main accent.
        engine.quickAccentsEnabled = true
        down(3, .character("e"))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 3))
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, "é")
        engine.cancelAllTouches()

        // The 123 page keeps its own holds.
        XCTAssertEqual(AccentCatalog.options(for: ".", uppercase: false), [".", "…"])
    }

    func testHeldPeriodOffersPunctuationThenDomainsInAddressFields() {
        engine.commaPeriodKeys = true
        engine.heldExtras = HeldKeyExtras(symbols: true, domains: KeyboardDomains.domains(for: .english, region: "US"))
        XCTAssertEqual(engine.heldHint(for: engine.layout.key(.character("."))!), "!?")
        down(1, .character("."))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
        XCTAssertEqual(engine.activeAccentMenu?.options.count, AccentCatalog.periodSymbols.count)
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, ".")
        up(1, .character("."))
        XCTAssertEqual(target.text, ".")

        target.keyboardType = .webSearch
        engine.configureForField()
        XCTAssertNil(engine.heldHint(for: engine.layout.key(.character("."))!), "domains take the period's place")
        down(2, .character("."))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 2))
        XCTAssertEqual(engine.activeAccentMenu?.options, [".us", ".edu", ".com", ".net", ".org"])
        XCTAssertEqual(engine.activeAccentMenu?.selectedOption, ".com")
        up(2, .character("."))
        XCTAssertEqual(target.text, "..com")

        // Domains alone: a text field's `.` keeps `.` and `…`.
        engine.heldExtras = HeldKeyExtras(domains: KeyboardDomains.domains(for: .english, region: "US"))
        target.keyboardType = .default
        engine.configureForField()
        down(3, .character("."))
        XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 3))
        XCTAssertEqual(engine.activeAccentMenu?.options.count, 2)
    }

    func testDomainListFollowsKeyboardLanguageAndRegion() {
        XCTAssertEqual(KeyboardDomains.domains(for: .english, region: "GB"), [".co.uk", ".com", ".ie", ".org", ".edu", ".eu", ".uk"])
        XCTAssertEqual(KeyboardDomains.domains(for: .english, region: "PL"), [".com", ".net", ".edu", ".org", ".us"], "no en_PL: en_US")
        XCTAssertEqual(KeyboardDomains.domains(for: .english, region: nil), [".com", ".net", ".edu", ".org", ".us"])
        XCTAssertEqual(KeyboardDomains.domains(for: .german, region: "AT").first, ".de")
        XCTAssertEqual(KeyboardDomains.domains(for: .german, region: "AT")[1], ".at")
        XCTAssertEqual(KeyboardDomains.domains(for: .spanish, region: "MX"), [".com", ".mx", ".org", ".edu", ".gob"])
        XCTAssertEqual(KeyboardDomains.domains(for: .portuguese, region: "PT"), [".com", ".pt", ".org", ".edu", ".eu"])
        XCTAssertEqual(KeyboardDomains.domains(for: .polish, region: "GB"), [".com", ".pl", ".org", ".edu", ".eu"], "the language's own")
        XCTAssertEqual(KeyboardDomains.domains(for: .arabic, region: "SA"), [".com", ".org", ".edu", ".net"], "Apple's default")
    }
}
