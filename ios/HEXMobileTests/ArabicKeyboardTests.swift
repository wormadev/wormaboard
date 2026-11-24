import UIKit
import XCTest
@testable import HEX

/// Settings › Labs › Arabic keyboard: Apple's Arabic letters and 123 pages, the gating,
/// the bundled Arabic model (`ar.hextm`) for taps and swipes, and Arabic dictation's
/// language pick and formatting.
@MainActor
final class ArabicKeyboardTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "ArabicKeyboardTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func letters(_ layout: KeyboardLayout, row: Int) -> [KeyboardKey] {
        layout.keys.filter {
            guard case .character = $0.kind else { return false }
            return $0.row == row
        }.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Layout

    /// Apple's iPhone Arabic keyboard (iOS 26.4 simulator, keys read left to right from the
    /// accessibility tree): eleven keys in rows 1 and 2, nine in row 3 from the left edge, and
    /// no shift, Arabic having no case.
    func testRowsAreApplesArabicWithNoShift() {
        let layout = KeyboardLayout(width: 402, language: .arabic)
        let rows = (0..<3).map { letters(layout, row: $0) }
        XCTAssertEqual(rows.map { $0.compactMap(\.character).joined() }, ["ضصثقفغعهخحج", "شسيبلاتنمكة", "ءظطذدزروى"])
        XCTAssertNil(layout.key(.shift), "no shift on Apple's Arabic keyboard")
        XCTAssertEqual(rows[2][0].frame.minX, rows[0][0].frame.minX, accuracy: 0.5, "ء sits under ض at the edge")
        XCTAssertEqual(rows[1].last?.frame.maxX ?? 0, rows[0].last?.frame.maxX ?? 0, accuracy: 0.5)
        let delete = try? XCTUnwrap(layout.key(.delete))
        XCTAssertGreaterThan(delete?.frame.minX ?? 0, rows[2].last?.frame.maxX ?? .infinity, "delete ends row 3")
        XCTAssertEqual(KeyboardLanguage.arabic.letterLayouts, [.own, .arabicPC])
        XCTAssertFalse(KeyboardLanguage.arabic.isLatin, "never a bilingual partner of a Latin layout")
    }

    /// Apple's Arabic – PC (iOS 27.0 simulator): ten columns in every row, row 3's nine letters
    /// from the edge and a delete key one column wide.
    func testPCRowsAreApplesWithDeleteInTheTenthColumn() throws {
        let layout = KeyboardLayout(width: 402, language: .arabic, letters: .arabicPC)
        let rows = (0..<3).map { letters(layout, row: $0) }
        XCTAssertEqual(rows.map { $0.compactMap(\.character).joined() }, ["ضصقفغعهخحج", "شسيبلاتنمك", "ظطذدزروةث"])
        XCTAssertNil(layout.key(.shift))
        let delete = try XCTUnwrap(layout.key(.delete))
        XCTAssertEqual(rows[2][0].frame.minX, rows[0][0].frame.minX, accuracy: 0.5)
        XCTAssertEqual(delete.frame.width, rows[0][0].frame.width, accuracy: 0.5)
        XCTAssertEqual(delete.frame.maxX, rows[0].last?.frame.maxX ?? 0, accuracy: 0.5)
        XCTAssertEqual(KeyboardLanguage.arabic.layoutName(.arabicPC), "العربية – PC")
    }

    /// The 123 page: Arabic-Indic digits with the Western ones held, ؛ for ;, and the Arabic
    /// comma and question mark; #+= keeps Western , and ? and has ٪.
    func testNumberPagesAreApplesArabicPages() {
        let numbers = KeyboardLayout.characterRows(for: .numbers, language: .arabic)
        XCTAssertEqual(numbers[0].joined(), "١٢٣٤٥٦٧٨٩٠")
        XCTAssertTrue(numbers[1].contains("؛"))
        XCTAssertEqual(numbers[2], [".", "،", "؟", "!", "'"])
        let symbols = KeyboardLayout.characterRows(for: .symbols, language: .arabic)
        XCTAssertTrue(symbols[0].contains("٪"))
        XCTAssertEqual(symbols[2], [".", ",", "?", "!", "'"])
        XCTAssertEqual(AccentCatalog.options(for: "١", uppercase: false, language: .arabic), ["١", "1"])
        XCTAssertEqual(AccentCatalog.options(for: "٠", uppercase: false, language: .arabic), ["٠", "0"])
        XCTAssertEqual(AccentCatalog.options(for: "؟", uppercase: false, language: .arabic), ["؟", "?", "¿"])
        XCTAssertEqual(AccentCatalog.options(for: "،", uppercase: false, language: .arabic), ["،", "٫", ","])
    }

    /// Apple's long presses (`Keyboard-ar.plist`): the hamza and alef forms nearest the key.
    func testHeldLettersOfferHamzaAndAlefForms() {
        XCTAssertEqual(AccentCatalog.options(for: "ا", uppercase: true, language: .arabic), ["ا", "ء", "آ", "إ", "أ"])
        XCTAssertEqual(AccentCatalog.options(for: "ء", uppercase: false, language: .arabic), ["ء", "ؤ", "ئ", "إ", "أ"])
        XCTAssertEqual(AccentCatalog.options(for: "ي", uppercase: false, language: .arabic), ["ي", "ئ", "ى"])
        XCTAssertEqual(AccentCatalog.options(for: "و", uppercase: false, language: .arabic), ["و", "ؤ"])
        XCTAssertEqual(AccentCatalog.options(for: "ل", uppercase: false, language: .arabic), ["ل", "لا"])
        XCTAssertNil(AccentCatalog.options(for: "س", uppercase: false, language: .arabic))
    }

    /// Letters go in typing order, the field lays them out right to left: tapping م ر ح ب ا
    /// writes "مرحبا", with no capital at a sentence start.
    func testKeysTypeInLogicalOrderWithoutCapitals() {
        let field = FixtureTextTarget()
        field.autocapitalizationType = .sentences
        let engine = FullKeyboardEngine(target: field)
        engine.width = 402
        engine.language = .arabic
        engine.configureForField()
        XCTAssertEqual(engine.autoCapitalizationMode, .none)
        for (id, letter) in "مرحبا".enumerated() {
            let key = engine.layout.key(.character(String(letter)))!
            let centre = CGPoint(x: key.frame.midX, y: key.frame.midY)
            engine.touchBegan(id: id, at: centre)
            engine.touchEnded(id: id, at: centre)
        }
        XCTAssertEqual(field.text, "مرحبا")
    }

    // MARK: - Gating

    func testArabicIsIgnoredWhileTheExperimentIsOff() {
        let settings = LanguageSettings(defaults: defaults)
        settings.keyboardLanguages = [.english, .arabic]
        settings.currentKeyboardLanguage = .arabic
        defaults.set(false, forKey: ArabicKeyboardExperiment.key)

        XCTAssertEqual(settings.keyboardLanguages, [.english], "a stored ar is ignored")
        XCTAssertNil(settings.currentKeyboardLanguage, "a stored ar is ignored")
        XCTAssertNil(KeyboardLanguage.matching("ar-SA", arabicEnabled: false))
        XCTAssertFalse(KeyboardLanguage.selectable(arabicEnabled: false).contains(.arabic))
        XCTAssertFalse(FullKeyboardSettings(defaults: defaults).arabicKeyboard, "off by default")
    }

    func testArabicAppearsWhileTheExperimentIsOn() {
        let settings = LanguageSettings(defaults: defaults)
        settings.keyboardLanguages = [.english, .arabic]
        settings.currentKeyboardLanguage = .arabic
        defaults.set(true, forKey: ArabicKeyboardExperiment.key)

        XCTAssertEqual(settings.keyboardLanguages, [.english, .arabic])
        XCTAssertEqual(settings.currentKeyboardLanguage, KeyboardLanguage.arabic)
        XCTAssertEqual(KeyboardLanguage.matching("ar-EG", arabicEnabled: true), KeyboardLanguage.arabic)
        XCTAssertEqual(KeyboardLanguage.automatic(dictationLanguage: "ar-SA", inputModes: [], preferredLanguages: []), .english,
                       "Automatic reads the App Group's flag, off here")
        XCTAssertTrue(KeyboardLanguage.selectable(arabicEnabled: true).contains(.arabic))
    }

    // MARK: - Dictation

    /// With the keyboard on العربية, Automatic dictates in Apple Speech's Arabic (ar-SA, the one
    /// locale DictationTranscriber lists on the iOS 26.4 simulator), and none where Speech has
    /// no Arabic.
    func testDictationFollowsTheArabicKeyboard() {
        defaults.set(true, forKey: ArabicKeyboardExperiment.key)
        let settings = LanguageSettings(defaults: defaults)
        settings.keyboardLanguages = [.english, .arabic]
        settings.currentKeyboardLanguage = .arabic
        settings.dictationFollowsKeyboard = true
        settings.supportedDictationLanguages = ["en-US", "ar-SA"]
        XCTAssertEqual(settings.keyboardDictationLanguage(preferred: ["en-US"]), "ar-SA")
        XCTAssertEqual(KeyboardLanguage.arabic.dictationLanguage(supported: ["ar-SA"], preferred: []), "ar-SA")
        XCTAssertEqual(KeyboardLanguage.arabic.dictationLanguage(supported: ["en-US"], preferred: []), nil)
        XCTAssertEqual(KeyboardLanguage.arabic.inputModeLanguage, "ar-SA")
    }

    /// Arabic dictation keeps its own punctuation: no "." after ؟, no space before ، or ؟, a
    /// sentence after ؟ starts one, and nothing is capitalised (Arabic has no case).
    func testFormatterKeepsArabicPunctuation() {
        XCTAssertEqual(TranscriptFormatter.format("كيف حالك ؟", style: .polished, language: "ar-SA"), "كيف حالك؟")
        XCTAssertEqual(TranscriptFormatter.format("مرحبا ، كيف حالك", style: .polished, language: "ar-SA"), "مرحبا، كيف حالك.")
        XCTAssertEqual(TranscriptFormatter.format("أولا ؛ ثانيا", style: .polished, language: "ar-SA"), "أولا؛ ثانيا.")
        XCTAssertEqual(TranscriptFormatter.format("هل أنت بخير؟", style: .casual, language: "ar-SA"), "هل أنت بخير؟")
        XCTAssertEqual(TranscriptFormatter.format("سأصل غدا", style: .verbatim, language: "ar-SA"), "سأصل غدا")
        XCTAssertEqual(TranscriptFormatter.format("مرحبا بك", style: .polished, language: "ar-SA", endsWithPeriod: false), "مرحبا بك")
        XCTAssertTrue(TranscriptFormatter.startsSentence(after: "هل وصلت؟ "))
        XCTAssertFalse(TranscriptFormatter.startsSentence(after: "وصلت، "))
    }

    /// Inserting a dictation into Arabic text: one space after the word before, none before
    /// the Arabic comma or question mark that follows.
    func testInsertionSpacesArabicLikeLatin() {
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "كيف حالك", beforeContext: "مرحبا", afterContext: "؟"), " كيف حالك")
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "صديقي", beforeContext: "مرحبا ", afterContext: "، كيف"), "صديقي")
        XCTAssertEqual(TranscriptFormatter.insertionText(for: "اليوم", beforeContext: "مرحبا", afterContext: "غدا"), " اليوم ")
    }

    // MARK: - The model

    private func model() throws -> TypingDecoderModel {
        try XCTUnwrap(TypingDecoderModel.bundled("ar"), "the Arabic model is bundled")
    }

    /// The model's words are spelled without tashkeel or tatweel, and so is a lookup; hamza
    /// forms, ة and ى stay letters of their own.
    func testModelLooksWordsUpWithoutTashkeel() throws {
        let model = try model()
        XCTAssertEqual(model.language, "ar")
        XCTAssertEqual(ArabicTyping.lookupForm("مَرْحَبًا"), "مرحبا")
        XCTAssertEqual(ArabicTyping.lookupForm("جمـــيل"), "جميل")
        XCTAssertEqual(ArabicTyping.lookupForm("أُسرة"), "أسرة", "the hamza stays")
        XCTAssertNotNil(model.index(of: "مرحبا"))
        XCTAssertEqual(model.index(of: "مَرْحَبًا"), model.index(of: "مرحبا"))
        XCTAssertNotEqual(model.index(of: "على"), model.index(of: "علي"), "ى and ي are other letters")
        XCTAssertNotEqual(model.index(of: "مدرسة"), model.index(of: "مدرسه"), "ة and ه are other letters")
        for word in ["في", "من", "أنا", "شكرا", "كيف", "الله", "السلام", "عليكم"] {
            XCTAssertNotNil(model.index(of: word), word)
        }
        XCTAssertTrue(model.hasPair("السلام", "عليكم"))
        XCTAssertTrue(model.nextWords(after: "عليكم", allowing: { _ in true }).contains("ورحمة"))
        XCTAssertTrue(model.completions(of: "شكر", after: nil, allowing: { _ in true }).contains("شكرا"))
    }

    /// The simulator's Arabic dictionary doesn't load ("Lexicon creation for ar failed"), so a
    /// stub stands in for the iPhone's: it knows the words meant and not the slips.
    private final class ArabicChecker: TextChecking {
        func isWordValid(_ word: String) -> Bool { ["السلام", "عليكم", "كيف"].contains(word) }
        func guesses(for word: String) -> [String] { [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    /// Spatial autocorrect reads Arabic taps with the model: taps on a neighbouring key come out
    /// as the word meant. A bare alef for أ is left alone where the bare spelling is common
    /// itself ("انا" is how many write "أنا"), as the model keeps it.
    func testSpatialAutocorrectFixesArabicTaps() throws {
        let field = FixtureTextTarget()
        let autocorrect = AutocorrectEngine(checker: ArabicChecker(), learnedWords: LearnedWordsStore(defaults: defaults))
        let engine = FullKeyboardEngine(target: field, autocorrect: autocorrect)
        engine.width = 393
        var now: TimeInterval = 100
        engine.clock = { now }
        engine.language = .arabic
        engine.configureForField()
        engine.autocorrect.decoder = TypingDecoder(model: try model())
        func type(_ word: String) {
            for letter in word {
                let key = engine.layout.key(.character(String(letter)))!.frame
                engine.touchBegan(id: 1, at: CGPoint(x: key.midX, y: key.midY))
                engine.touchEnded(id: 1, at: CGPoint(x: key.midX, y: key.midY))
                now += 0.2
            }
            let space = engine.layout.key(.space)!.frame
            engine.touchBegan(id: 1, at: CGPoint(x: space.midX, y: space.midY))
            engine.touchEnded(id: 1, at: CGPoint(x: space.midX, y: space.midY))
            now += 0.45
        }
        // ش typed for its neighbour س, and غ for its neighbour ف.
        type("الشلام")
        type("عليكم")
        type("كيغ")
        type("انا")
        XCTAssertEqual(field.text, "السلام عليكم كيف انا ")
    }

    // MARK: - Swipe typing

    private func swipeDecoder() throws -> (SwipeDecoder, TypingDecoder.Keys, TypingDecoderModel) {
        let model = try model()
        let keys = try XCTUnwrap(TypingDecoder.Keys(layout: KeyboardLayout(width: 390, language: .arabic)))
        return (SwipeDecoder(model: model), keys, model)
    }

    func testCleanArabicSwipesReadAsTheirWords() throws {
        let (decoder, keys, _) = try swipeDecoder()
        XCTAssertTrue(KeyboardLanguage.arabic.supportsSwipeTyping)
        for word in ["مرحبا", "شكرا", "السلام", "كيف", "حال", "اليوم", "جميل", "أنا", "إلى", "مدرسة"] {
            let read = decoder.decode(SwipePath.through(word, keys: keys), keys: keys).map(\.text)
            XCTAssertEqual(read.first, word, "\(word): \(read)")
        }
        let afterPeace = decoder.decode(SwipePath.through("عليكم", keys: keys), keys: keys, previous: "السلام").map(\.text)
        XCTAssertEqual(afterPeace.first, "عليكم")
    }

    /// How often a clean swipe through the model's 300 commonest words of two or more letters
    /// reads as the word first, as the measure of how well Arabic swipes decode (prints it).
    /// Two words on one path ("من", "منن") can't both win, so not every word can.
    func testCommonArabicWordsDecodeFromCleanSwipes() throws {
        let (decoder, keys, model) = try swipeDecoder()
        let common = (0..<model.wordCount)
            .filter { model.length($0) >= 2 }
            .sorted { model.unigramCost($0) < model.unigramCost($1) }
            .prefix(300)
            .map(model.word)
        var top1 = 0, top3 = 0
        for word in common {
            let read = decoder.decode(SwipePath.through(word, keys: keys), keys: keys).map(\.text)
            if read.first == word { top1 += 1 }
            if read.prefix(3).contains(word) { top3 += 1 }
        }
        print("ARABIC_SWIPE top1 \(top1)/\(common.count) top3 \(top3)/\(common.count)")
        XCTAssertGreaterThanOrEqual(Double(top1) / Double(common.count), 0.7)
        XCTAssertGreaterThanOrEqual(Double(top3) / Double(common.count), 0.9)
    }
}
