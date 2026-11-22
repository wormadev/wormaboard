import UIKit

/// Settings › Experiments › Clipboard history in the full keyboard: the strip's Clipboard chip
/// opens the list of kept copies over the keys (`ClipboardHistoryPanelView`), and tapping one
/// inserts it. What is kept and when the clipboard is read is `ClipboardHistory`'s.
extension FullKeyboardView {
    /// The strip offers Clipboard: the experiment on, Full Access, and something kept.
    var offersClipboardHistory: Bool {
        model.hasFullAccess && clipboardHistory.isEnabled && !clipboardHistory.items.isEmpty
    }

    /// The keyboard is on screen: keep the clipboard's text if it changed since the last look.
    func captureClipboardForHistory() {
        clipboardHistory.capture(hasFullAccess: hostController?.hasFullAccess == true)
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
        let panel = ClipboardHistoryPanelView(items: items)
        panel.palette = palette
        panel.onKeyDown = { [weak self] in self?.keyFeedback() }
        panel.onInsert = { [weak self] text in self?.insertFromClipboardHistory(text) }
        panel.onRemove = { [weak self] text in self?.removeFromClipboardHistory(text) }
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

    /// Inserted as the Paste chip inserts, but the text never reaches the typing log.
    private func insertFromClipboardHistory(_ text: String) {
        closeClipboardHistory()
        engine.forgetTextAroundKeys()
        engine.target.insertText(text)
        engine.textDidChange()
        refreshStrip()
        onTextEdit?()
    }

    private func removeFromClipboardHistory(_ text: String) {
        clipboardHistory.remove(text)
        let items = clipboardHistory.items
        if items.isEmpty {
            closeClipboardHistory()
        } else {
            clipboardHistoryPanel?.setItems(items)
        }
    }
}
