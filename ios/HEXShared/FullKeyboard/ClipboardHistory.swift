import UIKit

/// Settings › Experiments › Clipboard history: the last texts copied, newest first, kept in the
/// App Group on this device only. While the experiment is off, or without Full Access, nothing
/// reads the clipboard or keeps anything; the texts are never logged or sent anywhere, and
/// turning the experiment off deletes them (`FullKeyboardSettings.clipboardHistory`).
@MainActor
struct ClipboardHistory {
    static let capacity = 20
    /// Longer copies are skipped, not cut: inserting part of what was copied would surprise, and
    /// at this size twenty stay under about 160 KB in the App Group's defaults, which are
    /// rewritten whole on every change.
    static let maxItemBytes = 8 * 1024

    private enum Key {
        static let items = "keyboard.clipboardHistory.items"
        static let seenChange = "keyboard.clipboardHistory.seenChange"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var items: [String] { defaults?.stringArray(forKey: Key.items) ?? [] }

    var isEnabled: Bool { FullKeyboardSettings(defaults: defaults).clipboardHistory }

    /// The keyboard came on screen: keeps the clipboard's text when it changed since the last
    /// look. Each read can ask Allow Paste (Settings › Apps › Hex › Paste from Other Apps), so a
    /// copy is read at most once, refused or not.
    func capture(hasFullAccess: Bool, pasteboard: UIPasteboard = .general) {
        guard hasFullAccess, isEnabled, let defaults, pasteboard.hasStrings else { return }
        let change = pasteboard.changeCount
        guard defaults.integer(forKey: Key.seenChange) != change else { return }
        defaults.set(change, forKey: Key.seenChange)
        if let text = pasteboard.string { add(text) }
    }

    /// Hex's own Cut or Copy put `text` on the clipboard: kept without reading it back.
    func recordCopy(_ text: String, pasteboard: UIPasteboard = .general) {
        guard isEnabled, let defaults else { return }
        defaults.set(pasteboard.changeCount, forKey: Key.seenChange)
        add(text)
    }

    /// Puts `text` first, once; the oldest past `capacity` go.
    func add(_ text: String) {
        guard isEnabled, text.utf8.count <= Self.maxItemBytes,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let next = [text] + items.filter { $0 != text }
        defaults?.set(Array(next.prefix(Self.capacity)), forKey: Key.items)
    }

    func remove(_ text: String) {
        defaults?.set(items.filter { $0 != text }, forKey: Key.items)
    }

    /// Deletes every kept copy. The last clipboard change seen stays, so the copy still on the
    /// clipboard doesn't come straight back the next time the keyboard appears.
    func clear() {
        defaults?.removeObject(forKey: Key.items)
    }
}
