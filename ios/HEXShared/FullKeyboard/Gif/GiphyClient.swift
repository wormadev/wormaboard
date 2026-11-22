import Foundation

/// Settings › Experiments › GIFs: GIPHY search in the emoji panel. Off by default, stored as
/// `experiments.gifSearch` in the App Group. It works only with Full Access and a GIPHY key
/// in this build (`GiphyClient.make`); otherwise nothing reaches the network.
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

    /// The build's GIPHY key: Info.plist `GiphyAPIKey`, from the `GIPHY_API_KEY` build setting
    /// that the gitignored `Secrets.xcconfig` sets. Nil when the build has none.
    static func apiKey(in bundle: Bundle = .main) -> String? {
        guard let key = bundle.object(forInfoDictionaryKey: "GiphyAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded `$(GIPHY_API_KEY)` means the setting never reached the plist.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }
}

/// One GIF from GIPHY: a still for the grid, and the animated renditions a tap copies.
nonisolated struct GiphyGif: Equatable, Sendable {
    struct Rendition: Equatable, Sendable {
        let url: URL
        let width: Int
        let height: Int
        /// Bytes, when GIPHY says.
        let size: Int?
    }

    let id: String
    let title: String
    let still: Rendition
    /// Largest first: 200 pt tall, then 100 pt.
    let animated: [Rendition]

    /// The largest animated rendition within `limit` bytes.
    func copyRendition(limit: Int) -> Rendition? {
        animated.first { ($0.size ?? .max) <= limit }
    }
}

nonisolated enum GiphyError: Error, Equatable, CustomStringConvertible {
    case offline
    case timedOut
    case network(Int)
    case status(Int)
    case tooLarge
    case unreadable

    /// Never the request's URL, which holds the key and what was typed.
    var description: String {
        switch self {
        case .offline: "giphy offline"
        case .timedOut: "giphy timed out"
        case .network(let code): "giphy network error \(code)"
        case .status(let code): "giphy status \(code)"
        case .tooLarge: "giphy response too large"
        case .unreadable: "giphy response unreadable"
        }
    }

    /// The panel's quiet line for it.
    var message: String {
        switch self {
        case .offline, .timedOut, .network: String(localized: "Couldn't reach GIPHY")
        case .tooLarge: String(localized: "That GIF is too large")
        case .status, .unreadable: String(localized: "GIPHY isn't answering right now")
        }
    }

    /// URLError's description and userInfo carry the failing URL; only its code is kept.
    init(_ error: Error) {
        if let giphy = error as? GiphyError {
            self = giphy
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

/// GIPHY's search and trending endpoints. Only `make` builds one, so the experiment switch,
/// Full Access and the key gate every request at the source.
nonisolated struct GiphyClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let resultLimit = 24
    static let rating = "pg-13"
    /// What a copied GIF may weigh.
    static let copyLimit = 3_000_000
    /// What a search answer may weigh (24 results run about 40 KB).
    static let responseLimit = 1_000_000

    let apiKey: String
    private let fetch: Fetch

    private init(apiKey: String, fetch: @escaping Fetch) {
        self.apiKey = apiKey
        self.fetch = fetch
    }

    static func make(enabled: Bool, hasFullAccess: Bool, apiKey: String?, fetch: Fetch? = nil) -> GiphyClient? {
        guard enabled, hasFullAccess, let apiKey, !apiKey.isEmpty else { return nil }
        return GiphyClient(apiKey: apiKey, fetch: fetch ?? Self.urlSessionFetch)
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
    /// ("en", "fr-CA", "ar"); GIPHY takes its first part.
    func searchURL(query: String, language: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.giphy.com"
        components.path = trimmed.isEmpty ? "/v1/gifs/trending" : "/v1/gifs/search"
        var items = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: String(Self.resultLimit)),
            URLQueryItem(name: "rating", value: Self.rating),
        ]
        if !trimmed.isEmpty {
            let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
            items.append(URLQueryItem(name: "q", value: trimmed))
            items.append(URLQueryItem(name: "lang", value: code.lowercased()))
        }
        components.queryItems = items
        // URLComponents leaves "+" alone, which GIPHY would read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { preconditionFailure("GIPHY URL from fixed parts") }
        return url
    }

    func gifs(query: String, language: String) async throws -> [GiphyGif] {
        let data = try await load(searchURL(query: query, language: language), limit: Self.responseLimit)
        return try Self.parse(data)
    }

    /// A file GIPHY's search pointed to, refused past `limit` bytes.
    func load(_ url: URL, limit: Int) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(URLRequest(url: url))
        } catch {
            throw GiphyError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GiphyError.status(http.statusCode)
        }
        guard data.count <= limit else { throw GiphyError.tooLarge }
        return data
    }

    static func parse(_ data: Data) throws -> [GiphyGif] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GiphyError.unreadable
        }
        return response.data.compactMap { item in
            guard let still = item.images.fixedWidthSmallStill?.rendition else { return nil }
            let animated = [item.images.fixedHeight, item.images.fixedHeightSmall].compactMap { $0?.rendition }
            guard !animated.isEmpty else { return nil }
            return GiphyGif(id: item.id, title: item.title ?? "", still: still, animated: animated)
        }
    }

    private struct Response: Decodable {
        let data: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let title: String?
        let images: Images
    }

    private struct Images: Decodable {
        let fixedHeight: Image?
        let fixedHeightSmall: Image?
        let fixedWidthSmallStill: Image?

        enum CodingKeys: String, CodingKey {
            case fixedHeight = "fixed_height"
            case fixedHeightSmall = "fixed_height_small"
            case fixedWidthSmallStill = "fixed_width_small_still"
        }
    }

    /// GIPHY sends every number as a string.
    private struct Image: Decodable {
        let url: String?
        let width: String?
        let height: String?
        let size: String?

        var rendition: GiphyGif.Rendition? {
            guard let url = url.flatMap(URL.init(string:)), url.scheme == "https",
                  let width = width.flatMap(Int.init), let height = height.flatMap(Int.init),
                  width > 0, height > 0 else { return nil }
            return GiphyGif.Rendition(url: url, width: width, height: height, size: size.flatMap(Int.init))
        }
    }
}
