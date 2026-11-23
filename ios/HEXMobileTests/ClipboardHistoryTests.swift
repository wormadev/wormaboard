import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HEX

/// Settings › Experiments › Clipboard history: the last 20 copies, newest first, once each,
/// nothing read or kept while it's off or without Full Access, and deleted when turned off.
@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var pasteboard: UIPasteboard!
    private var folder: URL!

    override func setUp() async throws {
        suiteName = "ClipboardHistoryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = UIPasteboard.withUniqueName()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        UIPasteboard.remove(withName: pasteboard.name)
        try? FileManager.default.removeItem(at: folder)
    }

    private func enabledHistory() -> ClipboardHistory {
        FullKeyboardSettings(defaults: defaults).clipboardHistory = true
        return ClipboardHistory(defaults: defaults, folder: folder)
    }

    func testOffByDefaultKeepsAndReadsNothing() {
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).clipboardHistory, "off by default")
        let history = ClipboardHistory(defaults: defaults, folder: folder)
        pasteboard.string = "copied"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        history.recordCopy("cut", pasteboard: pasteboard)
        history.add("added")
        XCTAssertEqual(history.items.compactMap(\.text), [])
        XCTAssertNil(defaults.object(forKey: "keyboard.clipboardHistory.seenChange"), "no clipboard change looked at")
    }

    func testWithoutFullAccessReadsNothing() {
        let history = enabledHistory()
        pasteboard.string = "copied"
        history.capture(hasFullAccess: false, pasteboard: pasteboard)
        XCTAssertEqual(history.items.compactMap(\.text), [])
    }

    func testCaptureReadsEachCopyOnce() {
        let history = enabledHistory()
        pasteboard.string = "first"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items.compactMap(\.text), ["first"])

        // The same copy isn't read again, even once removed from the list.
        history.remove(.text("first"))
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items.compactMap(\.text), [])

        pasteboard.string = "second"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items.compactMap(\.text), ["second"])
    }

    /// Hex's own Cut or Copy is kept without the next appearance reading it back.
    func testOwnCopyIsKeptAndNotReadAgain() {
        let history = enabledHistory()
        pasteboard.string = "selected"
        history.recordCopy("selected", pasteboard: pasteboard)
        history.remove(.text("selected"))
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items.compactMap(\.text), [])
    }

    func testRecopiedTextMovesToFrontOnce() {
        let history = enabledHistory()
        for text in ["a", "b", "c", "a"] { history.add(text) }
        XCTAssertEqual(history.items.compactMap(\.text), ["a", "c", "b"])
    }

    func testKeepsTheLastTwenty() {
        let history = enabledHistory()
        for index in 0..<25 { history.add("copy \(index)") }
        XCTAssertEqual(history.items.count, ClipboardHistory.capacity)
        XCTAssertEqual(history.items.first?.text, "copy 24")
        XCTAssertEqual(history.items.last?.text, "copy 5")
    }

    func testSkipsBlankAndOversizedText() {
        let history = enabledHistory()
        history.add(" \n ")
        history.add(String(repeating: "x", count: ClipboardHistory.maxItemBytes + 1))
        XCTAssertEqual(history.items.compactMap(\.text), [])
        history.add(String(repeating: "x", count: ClipboardHistory.maxItemBytes))
        XCTAssertEqual(history.items.count, 1)
    }

    func testClearAndTurningOffDeleteEverything() {
        let history = enabledHistory()
        history.add("a")
        history.clear()
        XCTAssertEqual(history.items.compactMap(\.text), [])

        history.add("b")
        FullKeyboardSettings(defaults: defaults).clipboardHistory = false
        XCTAssertEqual(history.items.compactMap(\.text), [])
        XCTAssertNil(defaults.object(forKey: "keyboard.clipboardHistory.entries"))
    }

    /// An image is kept as a file, copied back onto the clipboard to paste, and deleted with it.
    func testKeepsImagesAsFiles() throws {
        let history = enabledHistory()
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        pasteboard.setData(png, forPasteboardType: UTType.png.identifier)
        XCTAssertTrue(history.capture(hasFullAccess: true, pasteboard: pasteboard))
        let item = try XCTUnwrap(history.items.first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(history.data(of: item), png)

        XCTAssertTrue(history.copyToPasteboard(item, pasteboard: pasteboard))
        XCTAssertFalse(history.capture(hasFullAccess: true, pasteboard: pasteboard), "not read back in")
        XCTAssertEqual(history.items.count, 1)

        history.remove(item)
        XCTAssertNil(history.data(of: item))
    }

    /// Texts kept before images and files still show.
    func testReadsTextsKeptBefore() {
        defaults.set(["old"], forKey: "keyboard.clipboardHistory.items")
        XCTAssertEqual(enabledHistory().items, [.text("old")])
    }
}
