import XCTest
@testable import HEX

/// Settings › Experiments › GIFs: GIPHY's answers parse into stills and copy renditions, the
/// URLs carry the right parameters, errors never repeat the URL (it holds the key and the
/// search), and nothing is requested while the switch is off, without Full Access or a key.
final class GiphyClientTests: XCTestCase {
    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var count: Int { lock.withLock { urls.count } }
        func append(_ url: URL?) { lock.withLock { if let url { urls.append(url) } } }
    }

    private static let key = "secret-key-123"

    private static func client(
        log: RequestLog = RequestLog(),
        status: Int = 200,
        body: Data = Data(#"{"data":[]}"#.utf8),
        error: Error? = nil
    ) -> GiphyClient? {
        GiphyClient.make(enabled: true, hasFullAccess: true, apiKey: key) { request in
            log.append(request.url)
            if let error { throw error }
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            return (body, response ?? URLResponse())
        }
    }

    private static let sample = Data("""
    {"data":[
      {"id":"abc","title":"Cat GIF","images":{
        "fixed_width_small_still":{"url":"https://media1.giphy.com/s.gif","width":"100","height":"80"},
        "fixed_height":{"url":"https://media1.giphy.com/200.gif","width":"250","height":"200","size":"4000000"},
        "fixed_height_small":{"url":"https://media1.giphy.com/100.gif","width":"125","height":"100","size":"900000"}
      }},
      {"id":"nostill","images":{"fixed_height":{"url":"https://media1.giphy.com/x.gif","width":"1","height":"1"}}},
      {"id":"http","images":{
        "fixed_width_small_still":{"url":"http://media1.giphy.com/s.gif","width":"100","height":"80"},
        "fixed_height":{"url":"https://media1.giphy.com/y.gif","width":"1","height":"1"}
      }}
    ],"pagination":{"count":3},"meta":{"status":200}}
    """.utf8)

    // MARK: - Parsing

    func testParsesStillsAndRenditionsAndSkipsIncompleteOnes() throws {
        let gifs = try GiphyClient.parse(Self.sample)
        XCTAssertEqual(gifs.map(\.id), ["abc"], "no still, or a non-HTTPS one, is skipped")
        let gif = try XCTUnwrap(gifs.first)
        XCTAssertEqual(gif.title, "Cat GIF")
        XCTAssertEqual(gif.still.width, 100)
        XCTAssertEqual(gif.still.height, 80)
        XCTAssertEqual(gif.animated.map(\.size), [4_000_000, 900_000])
    }

    func testCopyTakesTheLargestRenditionUnderTheLimit() throws {
        let gif = try XCTUnwrap(GiphyClient.parse(Self.sample).first)
        XCTAssertEqual(gif.copyRendition(limit: GiphyClient.copyLimit)?.url.lastPathComponent, "100.gif")
        XCTAssertEqual(gif.copyRendition(limit: 5_000_000)?.url.lastPathComponent, "200.gif")
        XCTAssertNil(gif.copyRendition(limit: 100))
    }

    func testUnreadableJSONIsAnError() {
        XCTAssertThrowsError(try GiphyClient.parse(Data("<html>".utf8))) { error in
            XCTAssertEqual(error as? GiphyError, .unreadable)
        }
    }

    // MARK: - URLs

    func testEmptyQueryAsksForTrending() throws {
        let client = try XCTUnwrap(Self.client())
        let url = client.searchURL(query: "  ", language: "en")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "api.giphy.com")
        XCTAssertEqual(url.path, "/v1/gifs/trending")
        XCTAssertNil(items.first { $0.name == "q" })
        XCTAssertEqual(items.first { $0.name == "rating" }?.value, "pg-13")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "24")
    }

    func testSearchCarriesQueryAndLanguage() throws {
        let client = try XCTUnwrap(Self.client())
        for (language, expected) in [("ar", "ar"), ("fr-CA", "fr"), ("sr-Latn", "sr"), ("en", "en")] {
            let url = client.searchURL(query: " قطة + dog ", language: language)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(url.path, "/v1/gifs/search")
            XCTAssertEqual(items.first { $0.name == "q" }?.value, "قطة + dog")
            XCTAssertEqual(items.first { $0.name == "lang" }?.value, expected)
            XCTAssertEqual(url.scheme, "https")
        }
        XCTAssertTrue(client.searchURL(query: "a+b", language: "en").absoluteString.contains("q=a%2Bb"))
    }

    func testErrorsNeverRepeatTheKeyOrTheSearch() async throws {
        let failingURL = "https://api.giphy.com/v1/gifs/search?api_key=\(Self.key)&q=private"
        let urlError = URLError(.cannotFindHost, userInfo: [NSURLErrorFailingURLStringErrorKey: failingURL])
        let client = try XCTUnwrap(Self.client(error: urlError))
        do {
            _ = try await client.gifs(query: "private", language: "en")
            XCTFail("expected a failure")
        } catch {
            let text = "\(error) \(String(describing: error)) \((error as? GiphyError)?.message ?? "")"
            XCTAssertFalse(text.contains(Self.key))
            XCTAssertFalse(text.contains("private"))
            XCTAssertEqual(error as? GiphyError, .network(URLError.Code.cannotFindHost.rawValue))
        }
    }

    func testHTTPFailureAndOversizeAreErrors() async throws {
        let unauthorized = try XCTUnwrap(Self.client(status: 403))
        await XCTAssertThrowsAsync(try await unauthorized.gifs(query: "", language: "en"), .status(403))
        let big = try XCTUnwrap(Self.client(body: Data(count: 2_000)))
        let url = try XCTUnwrap(URL(string: "https://media1.giphy.com/a.gif"))
        await XCTAssertThrowsAsync(try await big.load(url, limit: 1_000), .tooLarge)
    }

    // MARK: - Gating

    func testNoClientAndNoRequestWithoutTheSwitchFullAccessOrKey() {
        let log = RequestLog()
        let fetch: GiphyClient.Fetch = { request in
            log.append(request.url)
            return (Data(), URLResponse())
        }
        XCTAssertNil(GiphyClient.make(enabled: false, hasFullAccess: true, apiKey: Self.key, fetch: fetch))
        XCTAssertNil(GiphyClient.make(enabled: true, hasFullAccess: false, apiKey: Self.key, fetch: fetch))
        XCTAssertNil(GiphyClient.make(enabled: true, hasFullAccess: true, apiKey: nil, fetch: fetch))
        XCTAssertNil(GiphyClient.make(enabled: true, hasFullAccess: true, apiKey: "", fetch: fetch))
        XCTAssertEqual(log.count, 0)
        XCTAssertNotNil(GiphyClient.make(enabled: true, hasFullAccess: true, apiKey: Self.key, fetch: fetch))
    }

    func testTheSwitchDefaultsOff() throws {
        let suite = "GiphyClientTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = GifSearchSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        settings.isEnabled = true
        XCTAssertTrue(settings.isEnabled)
    }

    func testAKeyOnlyComesFromAnExpandedBuildSetting() {
        XCTAssertNil(GifSearchSettings.apiKey(in: Bundle(for: GiphyClientTests.self)), "the test bundle has none")
    }
}

private func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: GiphyError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? GiphyError, expected, file: file, line: line)
    }
}
