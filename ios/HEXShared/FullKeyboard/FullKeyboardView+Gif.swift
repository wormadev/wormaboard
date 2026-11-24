import UIKit

/// One GIF search, from the emoji panel's GIF button until the search ends: the gated client,
/// the results row, and the requests in flight. Everything here goes when it ends.
@MainActor
final class GifSearchSession {
    let client: KlipyClient
    let results = GifResultsView()
    var query: String?
    var searchTask: Task<Void, Never>?

    init(client: KlipyClient) {
        self.client = client
    }

    func tearDown() {
        searchTask?.cancel()
        results.purge()
        results.removeFromSuperview()
    }
}

/// Settings › Labs › GIFs: a GIF button beside the emoji panel's search opens a KLIPY
/// search the letter keys type into, as the emoji search does, with trending GIFs while the
/// query is empty. A tapped GIF types its link into the field, which messaging apps show as
/// the GIF (a keyboard can't insert images). Without the switch, Full Access or a key in this build there
/// is no button and no request (`KlipyClient.make`).
extension FullKeyboardView {
    static let gifSearchLift: CGFloat = 116
    static let gifStillLimit = 300_000
    static let gifCopiedNoteDuration: TimeInterval = 4
    static var gifCopiedNote: String { String(localized: "Copied, paste it") }

    func makeKlipyClient() -> KlipyClient? {
        KlipyClient.make(
            enabled: GifSearchSettings().isEnabled,
            hasFullAccess: model.hasFullAccess,
            apiKey: GifSearchSettings.apiKey()
        )
    }

    func beginGifSearch() {
        guard let panel = emojiPanel, !routedTarget.isSearching, let client = makeKlipyClient() else { return }
        typingLog?.ui("gif_search")
        // What you type is a search for KLIPY, never a typing log's.
        suspendedTypingLog = engine.typingLog
        engine.typingLog = nil
        routedTarget.query = ""
        panel.isHidden = true

        let field = EmojiSearchField()
        field.placeholder = String(localized: "Search KLIPY")
        field.palette = palette
        field.onClose = { [weak self] in self?.endEmojiSearch() }
        addSubview(field)
        emojiSearchField = field
        let session = GifSearchSession(client: client)
        session.results.palette = palette
        session.results.loadStill = { url in try await client.load(url, limit: Self.gifStillLimit) }
        session.results.onPick = { [weak self] index in self?.sendGif(at: index) }
        addSubview(session.results)
        gifSearch = session

        plane.isHidden = false
        emojiSearchLift = Self.gifSearchLift
        onPreferredHeightChange?()
        engine.configureForField()
        refreshReturnKey()
        refreshGifSearch()
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Typing changed the query: search again once typing pauses; trending while it's empty.
    func refreshGifSearch() {
        guard let session = gifSearch, let query = routedTarget.query else { return }
        emojiSearchField?.query = query
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed != session.query else { return }
        session.query = trimmed
        session.searchTask?.cancel()
        if session.results.items.isEmpty { session.results.message = String(localized: "Loading GIFs…") }
        let client = session.client
        let language = engine.language.rawValue
        session.searchTask = Task { [weak session] in
            do {
                if !trimmed.isEmpty { try await Task.sleep(for: .milliseconds(350)) }
                let gifs = try await client.gifs(query: trimmed, language: language)
                guard !Task.isCancelled, let session else { return }
                session.results.setItems(gifs)
                session.results.message = gifs.isEmpty ? String(localized: "No GIFs") : nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let session else { return }
                session.results.message = KlipyError(error).message
            }
        }
    }

    /// Types the GIF's link where the cursor is, as one insertion, and closes the panel.
    func sendGif(at index: Int) {
        guard let session = gifSearch, index < session.results.items.count else { return }
        keyFeedback()
        guard let rendition = session.results.items[index].copyRendition(limit: KlipyClient.copyLimit) else {
            session.results.message = KlipyError.tooLarge.message
            return
        }
        typingLog?.ui("gif_sent")
        routedTarget.document.insertText(rendition.url.absoluteString)
        onTextEdit?()
        closeEmojiPanel()
    }

    /// The strip says "Copied, paste it" for a few seconds (`refreshStrip`).
    func showGifCopiedNote() {
        gifCopiedHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.gifCopiedHideWork = nil
            self?.refreshStrip()
        }
        gifCopiedHideWork = work
        refreshStrip()
        UIAccessibility.post(notification: .announcement, argument: Self.gifCopiedNote)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.gifCopiedNoteDuration, execute: work)
    }

    func endGifSearch() {
        gifSearch?.tearDown()
        gifSearch = nil
    }
}
