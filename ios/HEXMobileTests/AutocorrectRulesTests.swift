import XCTest
@testable import HEX

/// Settings › Labs › Manage autocorrect rules: forgetting one learned pair, blocking a
/// replacement, imported rules per language, the CSV and JSON format, and nothing applied
/// while the experiment is off.
@MainActor
final class AutocorrectRulesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUp() async throws {
        suiteName = "AutocorrectRulesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    private final class Checker: TextChecking {
        var valid: Set<String> = ["the", "und", "hex"]
        var guessTable: [String: [String]] = ["teh": ["the"]]
        func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
        func guesses(for word: String) -> [String] { guessTable[word.lowercased()] ?? [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private func rules(on: Bool = true) -> AutocorrectRules {
        FullKeyboardSettings(defaults: defaults).manageAutocorrectRules = on
        return AutocorrectRules(defaults: defaults)
    }

    private func autocorrect(_ learning: TypingLearning) -> AutocorrectEngine {
        let engine = AutocorrectEngine(checker: Checker(), learnedWords: LearnedWordsStore(defaults: defaults))
        engine.applyLearning(learning)
        return engine
    }

    private func fix(_ engine: AutocorrectEngine, _ typed: String) -> String? {
        engine.replacementOnSpace(beforeInput: typed, field: .text, autocorrectionType: .default)?.replacement
    }

    func testOffByDefaultAndOffAppliesNothing() {
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).manageAutocorrectRules, "off by default")
        let store = AutocorrectRules(defaults: defaults)
        store.importRules([AutocorrectRule(language: "de", typed: "udn", correction: "und", count: 3)])
        store.block(AutocorrectBlock(typed: "teh", correction: "the"))
        let learned = TypingLearning(typos: ["wrok": "work"], rejected: [])
        XCTAssertEqual(learned.adding(store, language: .german), learned, "existing learning unchanged")
        XCTAssertEqual(fix(autocorrect(TypingLearning().adding(store, language: .english)), "teh"), "the")
        XCTAssertEqual(store.imported.count, 1, "kept while off")
    }

    func testForgettingOnePairKeepsTheOthers() {
        var snapshot = TypingJournalSnapshot()
        snapshot.corrections = [
            TypingJournalCorrection(kind: .retyped, typed: "wrok", final: "work", at: 1, language: "en"),
            TypingJournalCorrection(kind: .autocorrected, typed: "teh", final: "the", at: 2, language: "en"),
            TypingJournalCorrection(kind: .retyped, typed: "wrok", final: "work", at: 3, language: "en"),
            TypingJournalCorrection(kind: .undone, typed: "wrok", final: "work", at: 4, language: "en"),
        ]
        let url = folder.appendingPathComponent(TypingJournal.fileName)
        try? JSONEncoder().encode(snapshot).write(to: url)
        TypingJournal.forget(typed: "wrok", final: "work", in: folder)
        let left = TypingJournal.load(from: url).corrections
        XCTAssertEqual(left.map(\.typed), ["teh", "wrok"])
        XCTAssertEqual(left.last?.kind, .undone, "a rejection is not a learned fix, so it stays")
    }

    func testABlockedReplacementIsNeverMade() {
        let store = rules()
        let learned = TypingLearning(typos: ["figmaly": "Figma"], rejected: [])
        XCTAssertEqual(fix(autocorrect(learned), "Figmaly"), "Figma")
        XCTAssertEqual(fix(autocorrect(learned), "teh"), "the")
        store.block(AutocorrectBlock(typed: "Figmaly", correction: "Figma"))
        store.block(AutocorrectBlock(typed: "Figmaly", correction: "Figma"))
        XCTAssertEqual(store.blocked.count, 1, "once")
        XCTAssertEqual(fix(autocorrect(learned.adding(store, language: .english)), "teh"), "the", "other fixes still apply")
        store.block(AutocorrectBlock(typed: "teh", correction: "the"))
        let engine = autocorrect(learned.adding(store, language: .english))
        XCTAssertNil(fix(engine, "Figmaly"), "a learned fix")
        XCTAssertNil(fix(engine, "figmaly"), "in any case")
        XCTAssertNil(fix(engine, "teh"), "the dictionary's fix")
        store.unblock(AutocorrectBlock(typed: "figmaly", correction: "figma"))
        XCTAssertEqual(fix(autocorrect(learned.adding(store, language: .english)), "Figmaly"), "Figma")
    }

    func testAnImportedRuleAppliesOnlyInItsLanguage() {
        let store = rules()
        store.importRules([AutocorrectRule(language: "de", typed: "udn", correction: "und", count: 3)])
        XCTAssertEqual(fix(autocorrect(TypingLearning().adding(store, language: .german)), "udn"), "und")
        XCTAssertNil(fix(autocorrect(TypingLearning().adding(store, language: .english)), "udn"))
        let kept = TypingLearning(typos: [:], rejected: ["udn"]).adding(store, language: .german)
        XCTAssertEqual(fix(autocorrect(kept), "udn"), "und", "an imported rule wins over a word you kept")

        store.importRules([AutocorrectRule(language: "de", typed: "UDN", correction: "uns", count: 0)])
        XCTAssertEqual(store.imported.map(\.correction), ["uns"], "replaces the rule for the same word")
        store.remove(store.imported[0])
        XCTAssertEqual(TypingLearning().adding(store, language: .german), TypingLearning())
    }

    func testTheKeyboardReadsTheRules() {
        let store = rules()
        store.block(AutocorrectBlock(typed: "teh", correction: "the"))
        let engine = FullKeyboardEngine(target: FixtureTextTarget(), autocorrect: autocorrect(TypingLearning()))
        engine.autocorrectRules = store
        XCTAssertTrue(engine.autocorrect.learning.blocks("teh", to: "the"))
        FullKeyboardSettings(defaults: defaults).manageAutocorrectRules = false
        engine.syncLearning()
        XCTAssertFalse(engine.autocorrect.learning.blocks("teh", to: "the"), "off: not applied")
    }

    func testJSONAndCSVRoundTrip() throws {
        let rules = [
            AutocorrectRule(language: "de", typed: "udn", correction: "und", count: 3),
            AutocorrectRule(language: "en", typed: "alot", correction: "a lot, \"really\"", count: 0),
        ]
        for format in AutocorrectRulesFile.Format.allCases {
            let text = AutocorrectRulesFile.export(rules, as: format)
            let rows = try AutocorrectRulesFile.parse(Data(text.utf8)).get()
            XCTAssertEqual(try rows.map { try $0.result.get() }, rules, format.rawValue)
        }
        XCTAssertTrue(AutocorrectRulesFile.export(rules, as: .csv).hasPrefix("language,typed,correction,count\nde,udn,und,3\n"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(AutocorrectRulesFile.export(rules, as: .json).utf8)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    func testMalformedInputIsRejectedWithAReason() throws {
        let csv = """
        language,typed,correction,count
        de,udn,und,3
        xx,foo,bar,1
        en,two words,x,1
        en,teh,teh,1
        en,adn,and,-2
        en,adn
        de,UDN,uns,1
        """
        let rows = try AutocorrectRulesFile.parse(Data(csv.utf8)).get()
        XCTAssertEqual(rows.count, 7)
        XCTAssertNotNil(try? rows[0].result.get())
        for row in rows.dropFirst() {
            guard case .failure(let rejection) = row.result else { return XCTFail("row \(row.id) accepted") }
            XCTAssertFalse(rejection.reason.isEmpty)
        }

        func fails(_ text: String) -> Bool {
            if case .failure = AutocorrectRulesFile.parse(Data(text.utf8)) { true } else { false }
        }
        XCTAssertTrue(fails("typed,correction\nudn,und"), "wrong header")
        XCTAssertTrue(fails(#"{"version":2,"rules":[]}"#), "unknown version")
        XCTAssertTrue(fails(#"{"rules":"no"}"#))
        XCTAssertTrue(fails(String(repeating: "a", count: AutocorrectRulesFile.maxBytes + 1)), "too big")
        let many = "language,typed,correction,count\n" + (0...AutocorrectRulesFile.maxRules).map { "en,w\($0)x,w\($0),1" }.joined(separator: "\n")
        XCTAssertTrue(fails(many), "too many rules")

        let json = #"{"version":1,"rules":[{"language":"de","typed":"udn","correction":"und"},{"language":"de","typed":"x","correction":"y","count":"3"},7]}"#
        let jsonRows = try AutocorrectRulesFile.parse(Data(json.utf8)).get()
        XCTAssertEqual(try jsonRows[0].result.get().count, 0, "count is optional")
        XCTAssertNil(try? jsonRows[1].result.get(), "count must be a number")
        XCTAssertNil(try? jsonRows[2].result.get())
    }

    func testImportShowsConflicts() {
        let rules = [
            AutocorrectRule(language: "en", typed: "adn", correction: "and", count: 1),
            AutocorrectRule(language: "de", typed: "udn", correction: "uns", count: 1),
            AutocorrectRule(language: "en", typed: "wrok", correction: "wrong", count: 1),
            AutocorrectRule(language: "en", typed: "Figmaly", correction: "Figma", count: 1),
        ]
        let conflicts = AutocorrectRulesImportView.conflicts(
            rules,
            imported: [AutocorrectRule(language: "de", typed: "udn", correction: "und", count: 3)],
            blocked: [AutocorrectBlock(typed: "figmaly", correction: "figma")],
            learned: ["en": ["wrok": "work"]]
        )
        XCTAssertNil(conflicts[rules[0].key])
        XCTAssertEqual(Set(conflicts.keys), Set(rules.dropFirst().map(\.key)))
    }
}
