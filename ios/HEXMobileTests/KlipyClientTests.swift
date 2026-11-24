import XCTest
@testable import HEX

/// Settings › Labs › GIFs: KLIPY's answers parse into stills and copy renditions, the
/// URLs carry the right parameters, errors never repeat the URL (it holds the key and the
/// search), and nothing is requested while the switch is off, without Full Access or a key.
final class KlipyClientTests: XCTestCase {
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
    ) -> KlipyClient? {
        KlipyClient.make(enabled: true, hasFullAccess: true, apiKey: key) { request in
            log.append(request.url)
            if let error { throw error }
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            return (body, response ?? URLResponse())
        }
    }

    private static let sample = Data("""
    {"result":true,"data":{"data":[
      {"id":8041071659142944,"slug":"cat-1","title":"Cat GIF","type":"gif","file":{
        "md":{"gif":{"url":"https://static.klipy.com/md.gif","width":498,"height":400,"size":4000000}},
        "sm":{"gif":{"url":"https://static.klipy.com/sm.gif","width":220,"height":176,"size":900000},
              "jpg":{"url":"https://static.klipy.com/sm.jpg","width":220,"height":176,"size":7000}},
        "xs":{"gif":{"url":"https://static.klipy.com/xs.gif","width":90,"height":72,"size":60000},
              "jpg":{"url":"https://static.klipy.com/xs.jpg","width":90,"height":72,"size":2000}}
      }},
      {"id":2,"slug":"an-ad","type":"ad","file":{"xs":{"gif":{"url":"https://static.klipy.com/a.gif","width":1,"height":1},
                                                  "jpg":{"url":"https://static.klipy.com/a.jpg","width":1,"height":1}}}},
      {"id":3,"slug":"nostill","type":"gif","file":{"md":{"gif":{"url":"https://static.klipy.com/x.gif","width":1,"height":1}}}},
      {"id":4,"slug":"http","type":"gif","file":{"xs":{"jpg":{"url":"http://static.klipy.com/s.jpg","width":9,"height":9},
                                                       "gif":{"url":"https://static.klipy.com/y.gif","width":1,"height":1}}}}
    ],"current_page":1,"per_page":24,"has_next":true}}
    """.utf8)

    // MARK: - Parsing

    func testParsesStillsAndRenditionsAndSkipsAdsAndIncompleteOnes() throws {
        let gifs = try KlipyClient.parse(Self.sample)
        XCTAssertEqual(gifs.map(\.id), ["cat-1"], "an ad, no still, or a non-HTTPS one, is skipped")
        let gif = try XCTUnwrap(gifs.first)
        XCTAssertEqual(gif.title, "Cat GIF")
        XCTAssertEqual(gif.still.url.lastPathComponent, "xs.jpg")
        XCTAssertEqual(gif.still.width, 90)
        XCTAssertEqual(gif.animated.map(\.size), [4_000_000, 900_000, 60_000])
    }

    func testCopyTakesTheLargestRenditionUnderTheLimit() throws {
        let gif = try XCTUnwrap(KlipyClient.parse(Self.sample).first)
        XCTAssertEqual(gif.copyRendition(limit: KlipyClient.copyLimit)?.url.lastPathComponent, "sm.gif")
        XCTAssertEqual(gif.copyRendition(limit: 5_000_000)?.url.lastPathComponent, "md.gif")
        XCTAssertNil(gif.copyRendition(limit: 100))
    }

    func testUnreadableJSONIsAnError() {
        XCTAssertThrowsError(try KlipyClient.parse(Data("<html>".utf8))) { error in
            XCTAssertEqual(error as? KlipyError, .unreadable)
        }
    }

    // MARK: - URLs

    func testEmptyQueryAsksForTrending() throws {
        let client = try XCTUnwrap(Self.client())
        let url = client.searchURL(query: "  ", language: "en")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "api.klipy.com")
        XCTAssertEqual(url.path, "/api/v1/\(Self.key)/gifs/trending")
        XCTAssertNil(items.first { $0.name == "q" })
        XCTAssertNil(items.first { $0.name == "customer_id" }, "nothing identifies the person")
        XCTAssertEqual(items.first { $0.name == "content_filter" }?.value, "medium")
        XCTAssertEqual(items.first { $0.name == "per_page" }?.value, "24")
        XCTAssertEqual(items.first { $0.name == "locale" }?.value, "en")
    }

    func testSearchCarriesQueryAndLanguage() throws {
        let client = try XCTUnwrap(Self.client())
        for (language, expected) in [("ar", "ar"), ("fr-CA", "fr"), ("sr-Latn", "sr"), ("en", "en")] {
            let url = client.searchURL(query: " قطة + dog ", language: language)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(url.path, "/api/v1/\(Self.key)/gifs/search")
            XCTAssertEqual(items.first { $0.name == "q" }?.value, "قطة + dog")
            XCTAssertEqual(items.first { $0.name == "locale" }?.value, expected)
            XCTAssertEqual(url.scheme, "https")
        }
        XCTAssertTrue(client.searchURL(query: "a+b", language: "en").absoluteString.contains("q=a%2Bb"))
    }

    func testErrorsNeverRepeatTheKeyOrTheSearch() async throws {
        let failingURL = "https://api.klipy.com/api/v1/\(Self.key)/gifs/search?q=private"
        let urlError = URLError(.cannotFindHost, userInfo: [NSURLErrorFailingURLStringErrorKey: failingURL])
        let client = try XCTUnwrap(Self.client(error: urlError))
        do {
            _ = try await client.gifs(query: "private", language: "en")
            XCTFail("expected a failure")
        } catch {
            let text = "\(error) \(String(describing: error)) \((error as? KlipyError)?.message ?? "")"
            XCTAssertFalse(text.contains(Self.key))
            XCTAssertFalse(text.contains("private"))
            XCTAssertEqual(error as? KlipyError, .network(URLError.Code.cannotFindHost.rawValue))
        }
    }

    func testHTTPFailureAndOversizeAreErrors() async throws {
        let unauthorized = try XCTUnwrap(Self.client(status: 403))
        await XCTAssertThrowsAsync(try await unauthorized.gifs(query: "", language: "en"), .status(403))
        let big = try XCTUnwrap(Self.client(body: Data(count: 2_000)))
        let url = try XCTUnwrap(URL(string: "https://static.klipy.com/a.gif"))
        await XCTAssertThrowsAsync(try await big.load(url, limit: 1_000), .tooLarge)
    }

    // MARK: - Gating

    func testNoClientAndNoRequestWithoutTheSwitchFullAccessOrKey() {
        let log = RequestLog()
        let fetch: KlipyClient.Fetch = { request in
            log.append(request.url)
            return (Data(), URLResponse())
        }
        XCTAssertNil(KlipyClient.make(enabled: false, hasFullAccess: true, apiKey: Self.key, fetch: fetch))
        XCTAssertNil(KlipyClient.make(enabled: true, hasFullAccess: false, apiKey: Self.key, fetch: fetch))
        XCTAssertNil(KlipyClient.make(enabled: true, hasFullAccess: true, apiKey: nil, fetch: fetch))
        XCTAssertNil(KlipyClient.make(enabled: true, hasFullAccess: true, apiKey: "", fetch: fetch))
        XCTAssertEqual(log.count, 0)
        XCTAssertNotNil(KlipyClient.make(enabled: true, hasFullAccess: true, apiKey: Self.key, fetch: fetch))
    }

    func testTheSwitchDefaultsOff() throws {
        let suite = "KlipyClientTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = GifSearchSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        settings.isEnabled = true
        XCTAssertTrue(settings.isEnabled)
    }

    func testAKeyOnlyComesFromAnExpandedBuildSetting() {
        XCTAssertNil(GifSearchSettings.apiKey(in: Bundle(for: KlipyClientTests.self)), "the test bundle has none")
    }
}

private func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: KlipyError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? KlipyError, expected, file: file, line: line)
    }
}
