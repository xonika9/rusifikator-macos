import Foundation
import XCTest
@testable import Rusifikator

@MainActor
final class PreviewPublicationTests: XCTestCase {
    func testDefaultClockContinuesAndRestartsAfterIdle() async {
        var values: [String] = []
        let publication = PreviewPublication { values.append($0) }
        defer { publication.cancel() }
        publication.receive("first")
        await waitUntil { values == ["first"] }
        publication.receive("second")
        publication.receive("latest")
        await waitUntil { values == ["first", "latest"] }
        // Observe the actual worker becoming idle, rather than guessing how long it sleeps.
        await waitUntil {
            Mirror(reflecting: publication).children.first { $0.label == "delivery" }
                .map { Mirror(reflecting: $0.value).children.isEmpty } == true
        }
        publication.receive("restart")
        await waitUntil { values == ["first", "latest", "restart"] }
    }

    func testControlledClockCoalescesNextDeliveryAndRestartsAfterIdle() async {
        let clock = ManualNetworkClock()
        var values: [String] = []
        let publication = PreviewPublication(clock: clock) { values.append($0) }
        defer { publication.cancel() }
        publication.receive("first")
        await waitUntil { values == ["first"] && clock.sleepingCount == 1 }
        publication.receive("second")
        publication.receive("latest")
        clock.advance(by: .milliseconds(99))
        XCTAssertEqual(values, ["first"])
        clock.advance(by: .milliseconds(1))
        await waitUntil { values == ["first", "latest"] && clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(100))
        await waitUntil {
            Mirror(reflecting: publication).children.first { $0.label == "delivery" }
                .map { Mirror(reflecting: $0.value).children.isEmpty } == true
        }
        publication.receive("restart")
        await waitUntil { values == ["first", "latest", "restart"] && clock.sleepingCount == 1 }
        publication.receive("cancelled")
        publication.cancel()
        clock.advance(by: .milliseconds(100))
        await Task { @MainActor in }.value
        XCTAssertEqual(values, ["first", "latest", "restart"])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Expected publication state before deadline")
    }
}
