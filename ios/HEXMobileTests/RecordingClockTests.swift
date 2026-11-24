import XCTest
@testable import HEX

@MainActor
final class RecordingClockTests: XCTestCase {
    func testSubSecondRecordingClockUpdatesDoNotInvalidateObservationEveryFrame() {
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let defaults = UserDefaults(suiteName: "DotScopeClockChurnTests.\(UUID().uuidString)")!
        let controller = DictationController(
            keyboardBridge: KeyboardBridge(defaults: defaults),
            autoPrepareOnInit: false
        )

        let counter = Counter()
        withObservationTracking {
            _ = controller.recordingWholeSeconds
        } onChange: {
            counter.count += 1
        }

        for ms in stride(from: 33, through: 957, by: 33) {
            controller.updateRecordingDurationForTesting(Double(ms) / 1000.0)
        }
        XCTAssertEqual(counter.count, 0, "Sub-second 30 Hz meter ticks must not invalidate SwiftUI on @MainActor")

        controller.updateRecordingDurationForTesting(1.02)
        XCTAssertEqual(counter.count, 1, "Crossing a whole second should notify SwiftUI once")
    }
}
