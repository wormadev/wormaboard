import Foundation

/// Settings › Labs › GIFs: KLIPY GIF search in the emoji panel. Off by default, stored
/// as `experiments.gifSearch` in the App Group. It works only with Full Access and a KLIPY key
/// in this build (`KlipyClient.make`); otherwise nothing reaches the network.
nonisolated struct GifSearchSettings {
    static let key = "experiments.gifSearch"
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults?.bool(forKey: Self.key) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.key) }
    }

    /// The build's KLIPY key: Info.plist `KlipyAPIKey`, from the `KLIPY_API_KEY` build setting
    /// that the gitignored `Secrets.xcconfig` sets. Nil when the build has none.
    static func apiKey(in bundle: Bundle = .main) -> String? {
        guard let key = bundle.object(forInfoDictionaryKey: "KlipyAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded `$(KLIPY_API_KEY)` means the setting never reached the plist.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}

/// One GIF from KLIPY: a still for the grid, and the animated renditions a tap copies.
nonisolated struct KlipyGif: Equatable, Sendable {
    struct Rendition: Equatable, Sendable {
        let url: URL
        let width: Int
        let height: Int
        /// Bytes, when KLIPY says.
        let size: Int?
    }

    let id: String
    let title: String
    let still: Rendition
    /// Largest first: KLIPY's md, sm and xs GIFs.
    let animated: [Rendition]

    /// The largest animated rendition within `limit` bytes.
    func copyRendition(limit: Int) -> Rendition? {
        animated.first { ($0.size ?? .max) <= limit }
    }
}

nonisolated enum KlipyError: Error, Equatable, CustomStringConvertible {
    case offline
    case timedOut
    case network(Int)
    case status(Int)
    case tooLarge
    case unreadable

    /// Never the request's URL, which holds the key and what was typed.
    var description: String {
        switch self {
        case .offline: "klipy offline"
        case .timedOut: "klipy timed out"
        case .network(let code): "klipy network error \(code)"
        case .status(let code): "klipy status \(code)"
        case .tooLarge: "klipy response too large"
        case .unreadable: "klipy response unreadable"
        }
    }

    /// The panel's quiet line for it.
    var message: String {
        switch self {
        case .offline, .timedOut, .network: String(localized: "Couldn't reach KLIPY")
        case .tooLarge: String(localized: "That GIF is too large")
        case .status, .unreadable: String(localized: "KLIPY isn't answering right now")
        }
    }

    /// URLError's description and userInfo carry the failing URL; only its code is kept.
    init(_ error: Error) {
        if let klipy = error as? KlipyError {
            self = klipy
            return
        }
        guard let url = error as? URLError else {
            self = .unreadable
            return
        }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: self = .offline
        case .timedOut: self = .timedOut
        default: self = .network(url.code.rawValue)
        }
    }
}

/// KLIPY's GIF search and trending endpoints. Only `make` builds one, so the experiment
/// switch, Full Access and the key gate every request at the source. No `customer_id` is
/// sent: KLIPY marks it optional (personalization only), so nothing identifies the person.
nonisolated struct KlipyClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let resultLimit = 24
    /// KLIPY's levels are off, low, medium and high.
    static let contentFilter = "medium"
    /// What a copied GIF may weigh.
    static let copyLimit = 3_000_000
    /// What a search answer may weigh (24 results with only GIF and JPG renditions).
    static let responseLimit = 1_000_000

    let apiKey: String
    private let fetch: Fetch

    private init(apiKey: String, fetch: @escaping Fetch) {
        self.apiKey = apiKey
        self.fetch = fetch
    }

    static func make(enabled: Bool, hasFullAccess: Bool, apiKey: String?, fetch: Fetch? = nil) -> KlipyClient? {
        guard enabled, hasFullAccess, let apiKey, !apiKey.isEmpty else { return nil }
        return KlipyClient(apiKey: apiKey, fetch: fetch ?? Self.urlSessionFetch)
    }

    /// Ephemeral, so no cache or cookies are written; few connections, so loads stay bounded.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static let urlSessionFetch: Fetch = { request in
        try await session.data(for: request)
    }

    /// Trending for an empty query, else a search. `language` is a keyboard language code
    /// ("en", "fr-CA", "ar"); KLIPY's `locale` takes its first part.
    func searchURL(query: String, language: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.klipy.com"
        components.path = "/api/v1/\(apiKey)/gifs/" + (trimmed.isEmpty ? "trending" : "search")
        var items = [
            URLQueryItem(name: "per_page", value: String(Self.resultLimit)),
            URLQueryItem(name: "content_filter", value: Self.contentFilter),
            URLQueryItem(name: "format_filter", value: "gif,jpg"),
            URLQueryItem(name: "locale", value: code.lowercased()),
        ]
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        components.queryItems = items
        // URLComponents leaves "+" alone, which a server may read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { preconditionFailure("KLIPY URL from fixed parts") }
        return url
    }

    func gifs(query: String, language: String) async throws -> [KlipyGif] {
        let data = try await load(searchURL(query: query, language: language), limit: Self.responseLimit)
        return try Self.parse(data)
    }

    /// A file KLIPY's search pointed to, refused past `limit` bytes.
    func load(_ url: URL, limit: Int) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(URLRequest(url: url))
        } catch {
            throw KlipyError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KlipyError.status(http.statusCode)
        }
        guard data.count <= limit else { throw KlipyError.tooLarge }
        return data
    }

    /// GIFs only: an ad (`type` "ad", sent only when ads are switched on for the key in
    /// KLIPY's Partner Panel) or an item without a still or a GIF is left out.
    static func parse(_ data: Data) throws -> [KlipyGif] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw KlipyError.unreadable
        }
        return response.data.data.compactMap { item in
            guard item.type == nil || item.type == "gif", let file = item.file,
                  let still = (file.xs?.jpg ?? file.sm?.jpg)?.rendition else { return nil }
            let animated = [file.md, file.sm, file.xs].compactMap { $0?.gif?.rendition }
            guard !animated.isEmpty else { return nil }
            return KlipyGif(id: item.slug, title: item.title ?? "", still: still, animated: animated)
        }
    }

    private struct Response: Decodable {
        let data: Page
    }

    private struct Page: Decodable {
        let data: [Item]
    }

    private struct Item: Decodable {
        let slug: String
        let title: String?
        let type: String?
        let file: Sizes?
    }

    private struct Sizes: Decodable {
        let md: Formats?
        let sm: Formats?
        let xs: Formats?
    }

    private struct Formats: Decodable {
        let gif: Image?
        let jpg: Image?
    }

    private struct Image: Decodable {
        let url: String?
        let width: Int?
        let height: Int?
        let size: Int?

        var rendition: KlipyGif.Rendition? {
            guard let url = url.flatMap(URL.init(string:)), url.scheme == "https",
                  let width, let height, width > 0, height > 0 else { return nil }
            return KlipyGif.Rendition(url: url, width: width, height: height, size: size)
        }
    }
}
