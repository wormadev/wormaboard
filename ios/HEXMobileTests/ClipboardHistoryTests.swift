import UIKit
import XCTest
@testable import HEX

/// Settings › Experiments › Clipboard history: the last 20 copies, newest first, once each,
/// nothing read or kept while it's off or without Full Access, and deleted when turned off.
@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var pasteboard: UIPasteboard!

    override func setUp() async throws {
        suiteName = "ClipboardHistoryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = UIPasteboard.withUniqueName()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        UIPasteboard.remove(withName: pasteboard.name)
    }

    private func enabledHistory() -> ClipboardHistory {
        FullKeyboardSettings(defaults: defaults).clipboardHistory = true
        return ClipboardHistory(defaults: defaults)
    }

    func testOffByDefaultKeepsAndReadsNothing() {
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).clipboardHistory, "off by default")
        let history = ClipboardHistory(defaults: defaults)
        pasteboard.string = "copied"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        history.recordCopy("cut", pasteboard: pasteboard)
        history.add("added")
        XCTAssertEqual(history.items, [])
        XCTAssertNil(defaults.object(forKey: "keyboard.clipboardHistory.seenChange"), "no clipboard change looked at")
    }

    func testWithoutFullAccessReadsNothing() {
        let history = enabledHistory()
        pasteboard.string = "copied"
        history.capture(hasFullAccess: false, pasteboard: pasteboard)
        XCTAssertEqual(history.items, [])
    }

    func testCaptureReadsEachCopyOnce() {
        let history = enabledHistory()
        pasteboard.string = "first"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items, ["first"])

        // The same copy isn't read again, even once removed from the list.
        history.remove("first")
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items, [])

        pasteboard.string = "second"
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items, ["second"])
    }

    /// Hex's own Cut or Copy is kept without the next appearance reading it back.
    func testOwnCopyIsKeptAndNotReadAgain() {
        let history = enabledHistory()
        pasteboard.string = "selected"
        history.recordCopy("selected", pasteboard: pasteboard)
        history.remove("selected")
        history.capture(hasFullAccess: true, pasteboard: pasteboard)
        XCTAssertEqual(history.items, [])
    }

    func testRecopiedTextMovesToFrontOnce() {
        let history = enabledHistory()
        for text in ["a", "b", "c", "a"] { history.add(text) }
        XCTAssertEqual(history.items, ["a", "c", "b"])
    }

    func testKeepsTheLastTwenty() {
        let history = enabledHistory()
        for index in 0..<25 { history.add("copy \(index)") }
        XCTAssertEqual(history.items.count, ClipboardHistory.capacity)
        XCTAssertEqual(history.items.first, "copy 24")
        XCTAssertEqual(history.items.last, "copy 5")
    }

    func testSkipsBlankAndOversizedText() {
        let history = enabledHistory()
        history.add(" \n ")
        history.add(String(repeating: "x", count: ClipboardHistory.maxItemBytes + 1))
        XCTAssertEqual(history.items, [])
        history.add(String(repeating: "x", count: ClipboardHistory.maxItemBytes))
        XCTAssertEqual(history.items.count, 1)
    }

    func testClearAndTurningOffDeleteEverything() {
        let history = enabledHistory()
        history.add("a")
        history.clear()
        XCTAssertEqual(history.items, [])

        history.add("b")
        FullKeyboardSettings(defaults: defaults).clipboardHistory = false
        XCTAssertEqual(history.items, [])
        XCTAssertNil(defaults.object(forKey: "keyboard.clipboardHistory.items"))
    }
}
