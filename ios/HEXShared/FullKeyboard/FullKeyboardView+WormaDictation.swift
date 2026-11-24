import UIKit

/// Settings › Labs › New dictation key in the full keyboard: the Hex key loses its slide
/// menu, and a chevron beside it opens a shortcut tray
/// in place of the suggestions (`WormaDictationTrayView`). Off, there is no tray and the
/// Hex key is upstream's.
extension FullKeyboardView {
    func syncWormaDictationKey() {
        let on = FullKeyboardSettings().wormaDictationKey
        hexKey.hasTray = on
        guard on != (wormaTray != nil) else { return }
        if on {
            let tray = WormaDictationTrayView()
            tray.palette = palette
            tray.onChevron = { [weak self] in self?.toggleWormaTray() }
            tray.onItem = { [weak self] item in self?.wormaTrayItem(item) }
            tray.onKeyDown = { [weak self] in self?.keyFeedback() }
            tray.onStyle = { [weak self] style in
                self?.typingLog?.ui("style", [
                    TypingLogField("style", .string(style.rawValue)),
                    TypingLogField("from", .string("worma_tray")),
                ])
                self?.model.onStyleSelected?(style)
                self?.closeWormaTray()
            }
            tray.onLanguage = { [weak self] language in
                self?.typingLog?.ui("dictation_language", [TypingLogField("language", .string(language ?? "automatic"))])
                self?.model.onLanguageSelected?(language)
                self?.closeWormaTray()
            }
            stripView.addSubview(tray)
            wormaTray = tray
        } else {
            wormaTray?.removeFromSuperview()
            wormaTray = nil
        }
        setNeedsLayout()
        refreshStrip()
    }

    /// The slot beside the Hex key gives the chevron its room.
    func wormaSlotFrames(_ frames: [CGRect], hexOnLeading: Bool) -> [CGRect] {
        guard wormaTray != nil, frames.count == 3 else { return frames }
        let w = WormaDictationTrayView.chevronWidth
        var trimmed = frames
        if hexOnLeading {
            trimmed[0] = CGRect(x: frames[0].minX + w, y: frames[0].minY, width: max(0, frames[0].width - w), height: frames[0].height)
        } else {
            trimmed[2] = CGRect(x: frames[2].minX, y: frames[2].minY, width: max(0, frames[2].width - w), height: frames[2].height)
        }
        return trimmed
    }

    func layoutWormaTray(_ layout: KeyboardLayout) {
        guard let tray = wormaTray else { return }
        tray.frame = stripView.bounds
        tray.hexOnLeading = layout.hexOnLeading
        tray.textCenterY = layout.metrics.stripTextCenter
        tray.chipHeight = layout.metrics.stripChipHeight
    }

    /// From `refreshStrip`: true while the tray holds the strip, which then shows nothing of
    /// its own. A hint or notice takes the chevron's place and closes the tray.
    func refreshWormaTray(hintShows: Bool) -> Bool {
        guard let tray = wormaTray else { return false }
        // Nothing to offer: no chevron that opens an empty strip.
        let hides = hintShows || wormaTrayItems.isEmpty
        tray.hidesChevron = hides
        if hides { tray.show(nil, animated: false) }
        tray.isTranslating = model.isTranslating
        tray.style = model.style
        tray.language = model.dictationLanguage
        if case .items = tray.page { tray.show(.items(wormaTrayItems)) }
        return tray.isOpen
    }

    /// The chips leave first; the words come back once they're gone.
    func closeWormaTray(animated: Bool = true) {
        guard let tray = wormaTray, tray.isOpen else { return }
        tray.show(nil, animated: animated) { [weak self] in self?.refreshStrip() }
    }

    private func toggleWormaTray() {
        guard let tray = wormaTray else { return }
        switch tray.page {
        case .styles, .languages:
            tray.show(.items(wormaTrayItems))
            return
        case .items:
            closeWormaTray()
            return
        case nil:
            break
        }
        // As the old slide menu: its shortcuts are for dictation and the clipboard, which need Full Access.
        guard model.hasFullAccess else {
            showFullAccessHint()
            return
        }
        typingLog?.ui("worma_tray")
        // The words start leaving as the chips spring in just after.
        tray.show(.items(wormaTrayItems))
        refreshStrip()
    }

    /// The items shown in Settings whose feature this keyboard has now.
    var wormaTrayItems: [WormaTrayItem] {
        let shown = FullKeyboardSettings().wormaDictationTray
        return WormaTrayItem.allCases.filter { item in
            guard shown.contains(item) else { return false }
            switch item {
            case .gif: return makeKlipyClient() != nil
            case .clipboard: return model.hasFullAccess && clipboardHistory.isEnabled
            case .translate: return model.showsTranslationSwitch
            case .language: return model.showsLanguageSwitch && !model.languageChoices.isEmpty
            case .style, .settings: return true
            }
        }
    }

    private func wormaTrayItem(_ item: WormaTrayItem) {
        guard let tray = wormaTray else { return }
        switch item {
        case .gif:
            closeWormaTray(animated: false)
            openEmojiPanel()
            beginGifSearch()
        case .clipboard:
            closeWormaTray(animated: false)
            openClipboardHistory()
        case .translate:
            let on = !model.isTranslating
            typingLog?.ui("translate", [TypingLogField("on", .bool(on))])
            // A switch: the tray stays so its state shows.
            model.onTranslationToggled?(on)
        case .style:
            tray.show(.styles)
        case .language:
            let choices = model.languageChoices
            let names = DictationLanguageSwitch.nativeNames(for: choices, supported: choices + model.moreLanguages)
            let automatic = model.automaticLanguage.map {
                "\(String(localized: "Automatic")) (\(DictationLanguageSwitch.nativeName(for: $0, supported: choices + model.moreLanguages)))"
            }
            tray.languages = [(id: nil, name: automatic ?? String(localized: "Automatic"))] + choices.map { (id: $0, name: names[$0] ?? $0) }
            tray.show(.languages)
        case .settings:
            closeWormaTray()
            model.onOpenURL?(KeyboardLaunchRequest.setup.url)
        }
    }
}
