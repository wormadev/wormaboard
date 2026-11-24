import UIKit

/// Settings › Labs › Clipboard history in the full keyboard: the strip's Clipboard chip
/// opens the list of kept copies over the keys (`ClipboardHistoryPanelView`), and tapping one
/// inserts it. What is kept and when the clipboard is read is `ClipboardHistory`'s.
extension FullKeyboardView {
    /// The strip offers Clipboard: the experiment on, Full Access, and something kept.
    var offersClipboardHistory: Bool {
        model.hasFullAccess && clipboardHistory.isEnabled && !clipboardHistory.items.isEmpty
    }

    /// The keyboard is on screen (and every second while it stays): keep what was copied if
    /// the clipboard changed since the last look.
    func captureClipboardForHistory() {
        guard clipboardHistory.capture(hasFullAccess: hostController?.hasFullAccess == true) else { return }
        clipboardHistoryPanel?.setItems(clipboardHistory.items)
        refreshStrip()
    }

    func openClipboardHistory() {
        guard clipboardHistoryPanel == nil, emojiPanel == nil, !showsRecording else { return }
        let items = clipboardHistory.items
        guard !items.isEmpty else { return }
        keyFeedback()
        engine.commitHangulComposition()
        dismissStyleMenu()
        plane.cancelAllTouches()
        let panel = ClipboardHistoryPanelView(items: items, history: clipboardHistory)
        panel.palette = palette
        panel.onKeyDown = { [weak self] in self?.keyFeedback() }
        panel.onInsert = { [weak self] item in self?.insertFromClipboardHistory(item) }
        panel.onRemove = { [weak self] item in self?.removeFromClipboardHistory(item) }
        panel.onClear = { [weak self] in
            self?.clipboardHistory.clear()
            self?.closeClipboardHistory()
        }
        panel.onLetters = { [weak self] in self?.closeClipboardHistory() }
        insertSubview(panel, belowSubview: callout)
        clipboardHistoryPanel = panel
        for view in [plane, stripView, hexKey, globeButton] as [UIView] { view.isHidden = true }
        setNeedsLayout()
    }

    func closeClipboardHistory() {
        guard let panel = clipboardHistoryPanel else { return }
        panel.removeFromSuperview()
        clipboardHistoryPanel = nil
        for view in [plane, stripView, hexKey] as [UIView] {
            view.isHidden = false
            view.alpha = 1
        }
        refreshStrip()
        setNeedsLayout()
    }

    func layoutClipboardHistory() {
        guard let panel = clipboardHistoryPanel else { return }
        panel.frame = bounds
        panel.metrics = engine.layout.metrics
        panel.horizontalInset = engine.layout.horizontalInset
    }

    /// Text is inserted as the Paste chip inserts, but never reaches the typing log. A keyboard
    /// can't insert an image or file, so those go back on the clipboard to paste, as a GIF does.
    private func insertFromClipboardHistory(_ item: ClipboardItem) {
        closeClipboardHistory()
        guard let text = item.text else {
            if clipboardHistory.copyToPasteboard(item) { showGifCopiedNote() }
            return
        }
        engine.forgetTextAroundKeys()
        engine.target.insertText(text)
        engine.textDidChange()
        refreshStrip()
        onTextEdit?()
    }

    private func removeFromClipboardHistory(_ item: ClipboardItem) {
        clipboardHistory.remove(item)
        let items = clipboardHistory.items
        if items.isEmpty {
            closeClipboardHistory()
        } else {
            clipboardHistoryPanel?.setItems(items)
        }
    }
}
