import UIKit
import UniformTypeIdentifiers

/// One kept copy: text, or an image or file whose bytes sit in the App Group's
/// `ClipboardHistory` folder under `file`.
struct ClipboardItem: Codable, Equatable {
    enum Kind: String, Codable { case text, image, file }

    var kind: Kind
    var text: String?
    /// The stored file's name in `ClipboardHistory.folder`.
    var file: String?
    /// The pasteboard type it came as, for putting it back (`public.png`, `com.adobe.pdf`…).
    var type: String?
    /// A file's name as the copying app gave it.
    var name: String?

    static func text(_ text: String) -> ClipboardItem { ClipboardItem(kind: .text, text: text) }
}

/// Settings › Experiments › Clipboard history: the last copies (text, images and files), newest
/// first, kept in the App Group on this device only. While the experiment is off, or without
/// Full Access, nothing reads the clipboard or keeps anything; nothing is logged or sent
/// anywhere, and turning the experiment off deletes it all (`FullKeyboardSettings.clipboardHistory`).
///
/// A keyboard only runs while it's on screen, so of several copies made while it's away only
/// the last one can be kept; while it's up, every copy is (`capture` is polled).
@MainActor
struct ClipboardHistory {
    static let capacity = 20
    /// Longer texts are skipped, not cut: inserting part of what was copied would surprise, and
    /// at this size twenty stay under about 160 KB in the App Group's defaults, which are
    /// rewritten whole on every change.
    static let maxItemBytes = 8 * 1024
    /// Images and files past this are skipped.
    static let maxFileBytes = 15 * 1024 * 1024

    private enum Key {
        static let entries = "keyboard.clipboardHistory.entries"
        /// Before images and files: the texts alone.
        static let items = "keyboard.clipboardHistory.items"
        static let seenChange = "keyboard.clipboardHistory.seenChange"
    }

    private let defaults: UserDefaults?
    private let folder: URL?

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup),
        folder: URL? = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KeyboardBridge.appGroup)?
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
    ) {
        self.defaults = defaults
        self.folder = folder
    }

    var items: [ClipboardItem] {
        if let data = defaults?.data(forKey: Key.entries),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            return items
        }
        return (defaults?.stringArray(forKey: Key.items) ?? []).map(ClipboardItem.text)
    }

    var isEnabled: Bool { FullKeyboardSettings(defaults: defaults).clipboardHistory }

    /// Keeps what is on the clipboard when it changed since the last look. Checking the change
    /// count asks nothing, so this runs every second while the keyboard is up; each read can ask
    /// Allow Paste (Settings › Apps › WormaBoard › Paste from Other Apps), so a copy is read at
    /// most once, refused or not, and in one read. Returns whether anything was kept.
    @discardableResult
    func capture(hasFullAccess: Bool, pasteboard: UIPasteboard = .general) -> Bool {
        guard hasFullAccess, isEnabled, let defaults else { return false }
        let change = pasteboard.changeCount
        guard defaults.integer(forKey: Key.seenChange) != change else { return false }
        defaults.set(change, forKey: Key.seenChange)
        guard let item = read(pasteboard) else { return false }
        insert(item)
        return true
    }

    private func read(_ pasteboard: UIPasteboard) -> ClipboardItem? {
        let types = pasteboard.types
        if pasteboard.hasImages {
            let imageType = types.first { UTType($0)?.conforms(to: .image) == true }
            if let imageType, let data = pasteboard.data(forPasteboardType: imageType) {
                return store(data, kind: .image, type: imageType, name: nil)
            }
            return pasteboard.image?.pngData().flatMap { store($0, kind: .image, type: UTType.png.identifier, name: nil) }
        }
        if pasteboard.hasStrings { return pasteboard.string.map(ClipboardItem.text) }
        if pasteboard.hasURLs { return pasteboard.url.map { ClipboardItem.text($0.absoluteString) } }
        let fileType = types.first { type in
            guard let uti = UTType(type) else { return false }
            return uti.conforms(to: .data) && !uti.conforms(to: .text) && !uti.conforms(to: .url)
        }
        guard let fileType, let data = pasteboard.data(forPasteboardType: fileType) else { return nil }
        let name = pasteboard.itemProviders.first?.suggestedName
        return store(data, kind: .file, type: fileType, name: name)
    }

    private func store(_ data: Data, kind: ClipboardItem.Kind, type: String, name: String?) -> ClipboardItem? {
        guard data.count <= Self.maxFileBytes, let folder else { return nil }
        let ext = UTType(type)?.preferredFilenameExtension ?? "bin"
        let file = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(file), options: .atomic)
        } catch {
            return nil
        }
        return ClipboardItem(kind: kind, file: file, type: type, name: name)
    }

    /// An image's or file's bytes.
    func data(of item: ClipboardItem) -> Data? {
        guard let file = item.file, let folder else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(file))
    }

    /// Puts an image or file back on the clipboard for the field to paste, without the next
    /// look reading it in again.
    func copyToPasteboard(_ item: ClipboardItem, pasteboard: UIPasteboard = .general) -> Bool {
        guard let type = item.type, let data = data(of: item) else { return false }
        pasteboard.setData(data, forPasteboardType: type)
        defaults?.set(pasteboard.changeCount, forKey: Key.seenChange)
        insert(item)
        return true
    }

    /// Hex's own Cut or Copy put `text` on the clipboard: kept without reading it back.
    func recordCopy(_ text: String, pasteboard: UIPasteboard = .general) {
        guard isEnabled, let defaults else { return }
        defaults.set(pasteboard.changeCount, forKey: Key.seenChange)
        add(text)
    }

    /// Puts `text` first, once; the oldest past `capacity` go.
    func add(_ text: String) {
        guard text.utf8.count <= Self.maxItemBytes,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        insert(.text(text))
    }

    private func insert(_ item: ClipboardItem) {
        guard isEnabled else { return }
        let current = items
        // The same image copied again comes back with a new file: matched by its bytes.
        let duplicate: (ClipboardItem) -> Bool = { other in
            if item.kind == .text { return other == item }
            return other == item || (other.kind == item.kind && other.type == item.type && data(of: other) == data(of: item))
        }
        let dropped = current.filter { duplicate($0) && $0.file != item.file }
        let next = [item] + current.filter { !duplicate($0) }
        let kept = Array(next.prefix(Self.capacity))
        deleteFiles(of: dropped + next.dropFirst(Self.capacity))
        save(kept)
    }

    func remove(_ item: ClipboardItem) {
        deleteFiles(of: [item])
        save(items.filter { $0 != item })
    }

    /// Deletes every kept copy. The last clipboard change seen stays, so the copy still on the
    /// clipboard doesn't come straight back the next time the keyboard appears.
    func clear() {
        defaults?.removeObject(forKey: Key.entries)
        defaults?.removeObject(forKey: Key.items)
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private func save(_ items: [ClipboardItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: Key.entries)
        defaults?.removeObject(forKey: Key.items)
    }

    private func deleteFiles(of items: some Sequence<ClipboardItem>) {
        guard let folder else { return }
        for file in items.compactMap(\.file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}
