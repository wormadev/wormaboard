import XCTest
@testable import HEX

/// Apple's speech assets, with the calls swapped out: a hung reservation or release must not
/// hold every later one.
@available(iOS 26.0, *)
final class AppleSpeechAssetReservationsTests: XCTestCase {
    func testAnAcquireThatNeverAnswersIsForgottenSoTheNextOneAsksAgain() async throws {
        let locale = Locale(identifier: "en-US")
        let calls = CallCounter()
        let reservations = AppleSpeechAssetReservations(
            reserver: { _ in
                if calls.next() == 1 {
                    try? await Task.sleep(for: .seconds(60))
                }
            },
            releaser: { _ in }
        )
        do {
            try await reservations.acquire(locale, limit: .milliseconds(150))
            XCTFail("the first call never answers")
        } catch {
            XCTAssertTrue(error is SpeechModelUnresponsive, "\(error)")
        }

        // The hung call was forgotten, so this starts a fresh one instead of joining it.
        try await reservations.acquire(locale, limit: .milliseconds(150))
        XCTAssertEqual(calls.count, 2)
        await reservations.release(locale)
    }

    func testACancelledWaitOnAReleaseForgetsItSoTheNextReservationIsNotHeld() async throws {
        let locale = Locale(identifier: "en-US")
        let releaseGate = AsyncGate()
        let reservations = AppleSpeechAssetReservations(
            reserver: { _ in },
            releaser: { _ in await releaseGate.wait() }
        )
        try await reservations.acquire(locale, limit: .milliseconds(150))

        let releasing = Task { await reservations.release(locale) }
        try await Task.sleep(for: .milliseconds(50))
        let waiting = Task { try await reservations.acquire(locale, limit: .seconds(30)) }
        try await Task.sleep(for: .milliseconds(50))
        waiting.cancel()
        _ = try? await waiting.value

        // The cancelled wait must have forgotten the hung release: a new reservation returns at
        // once rather than waiting on it.
        let clock = ContinuousClock()
        let started = clock.now
        try await reservations.acquire(locale, limit: .seconds(2))
        XCTAssertLessThan(clock.now - started, .seconds(1))

        releaseGate.open()
        await releasing.value
        await reservations.release(locale)
    }
}

/// How many times the fake reservation was asked for.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int { lock.withLock { calls } }

    /// The 1-based number of this call.
    func next() -> Int {
        lock.withLock {
            calls += 1
            return calls
        }
    }
}

/// A release that hasn't finished until the test opens it.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false

    func open() {
        lock.withLock { opened = true }
    }

    func wait() async {
        while !lock.withLock({ opened }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
