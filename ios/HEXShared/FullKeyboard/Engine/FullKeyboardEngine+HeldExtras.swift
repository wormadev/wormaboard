import CoreGraphics

/// Settings › Labs › Symbols on held keys and Domains on held period, as the keyboard
/// reads them (`FullKeyboardView.syncHeldExtras`). Both off holds what every key held before.
nonisolated struct HeldKeyExtras: Equatable, Sendable {
    var symbols = false
    /// The keyboard's `KeyboardDomains`, empty while Domains on held period is off.
    var domains: [String] = []
}

@MainActor
extension FullKeyboardEngine {
    /// Letters' symbols and `.`'s punctuation: an iPhone's letters page only, so the 123 and
    /// #+= pages keep their own holds and a docked iPad its key flicks.
    private var holdsSymbols: Bool {
        heldExtras.symbols && layerState.layer == .letters && layout.metrics.pad == nil
    }

    func heldOptions(for base: String, key: KeyboardKey) -> [String]? {
        AccentCatalog.options(
            for: base, uppercase: isUppercase, language: layout.language, letters: layout.letters,
            field: layout.field, domains: heldExtras.domains, symbols: holdsSymbols, topRow: key.row == 0
        )
    }

    func heldArrangement(for base: String, key: KeyboardKey) -> AccentArrangement? {
        AccentCatalog.arrangement(
            for: base, uppercase: isUppercase, language: layout.language, letters: layout.letters,
            field: layout.field, domains: heldExtras.domains, symbols: holdsSymbols, topRow: key.row == 0
        )
    }

    /// Domains' cells fit their text (`.co.uk`); every other callout keeps the key's width.
    func heldCellWidth(for options: [String], key: KeyboardKey) -> CGFloat? {
        guard options == heldExtras.domains else { return nil }
        return max(key.frame.width + AccentMenu.cellGrowth, AccentMenu.textWidth(of: options))
    }

    /// A held letter's callout opens on its symbol, so letting go types it; Quick accents then
    /// moves it to the letter's main accent where it has one.
    func selectingHeldSymbol(_ menu: AccentMenu, on key: KeyboardKey) -> AccentMenu {
        guard holdsSymbols, let letter = key.character,
              let symbol = AccentCatalog.letterSymbol(for: letter, topRow: key.row == 0),
              let index = menu.options.firstIndex(of: symbol) else { return menu }
        var selected = menu
        selected.selectedIndex = index
        return selected
    }

    /// The small hint in a key's corner: a letter's symbol, and `!?` on a `.` that holds punctuation.
    func heldHint(for key: KeyboardKey) -> String? {
        guard holdsSymbols, let character = key.character else { return nil }
        if character == "." { return layout.field.holdsDomains && heldExtras.domains.count > 1 ? nil : "!?" }
        return AccentCatalog.letterSymbol(for: character, topRow: key.row == 0)
    }
}
