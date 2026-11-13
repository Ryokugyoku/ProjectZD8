import XCTest
@testable import ProjectZD8

final class DistanceTrackerTests: XCTestCase {
    func testSourceMapping() {
        XCTAssertEqual(DistanceTracker.source(for: DriveFlowFixtures.zd8Odometer), .vehicleSpecificOdometer)
        XCTAssertEqual(DistanceTracker.source(for: DriveFlowFixtures.odometer), .odometer)
        XCTAssertEqual(DistanceTracker.source(for: DriveFlowFixtures.sinceCleared), .distanceSinceCodesCleared)
        XCTAssertNil(DistanceTracker.source(for: DriveFlowFixtures.rpm))
    }

    func testPriorityPrefersVehicleSpecificThenOdometerThenSinceCleared() {
        var tracker = DistanceTracker()
        XCTAssertEqual(tracker.record(10, for: DriveFlowFixtures.sinceCleared)?.source, .distanceSinceCodesCleared)
        XCTAssertEqual(tracker.record(5000, for: DriveFlowFixtures.odometer)?.source, .odometer)
        let specific = tracker.record(9000, for: DriveFlowFixtures.zd8Odometer)
        XCTAssertEqual(specific, DistanceTracker.Reading(source: .vehicleSpecificOdometer, startKilometers: 9000, endKilometers: 9000))
        // A lower-priority source no longer changes what is persisted.
        XCTAssertNil(tracker.record(11, for: DriveFlowFixtures.sinceCleared))
        XCTAssertEqual(tracker.current?.source, .vehicleSpecificOdometer)
    }

    func testStartIsFirstValueAndEndTracksLatest() {
        var tracker = DistanceTracker()
        _ = tracker.record(100, for: DriveFlowFixtures.odometer)
        let reading = tracker.record(100.4, for: DriveFlowFixtures.odometer)
        XCTAssertEqual(try XCTUnwrap(reading).distanceKilometers, 0.4, accuracy: 1e-9)
    }

    func testUnchangedValueIsNotReportedAgain() {
        var tracker = DistanceTracker()
        XCTAssertNotNil(tracker.record(100, for: DriveFlowFixtures.odometer))
        XCTAssertNil(tracker.record(100, for: DriveFlowFixtures.odometer))
    }

    func testCounterRollbackRestartsStart() {
        var tracker = DistanceTracker()
        _ = tracker.record(50, for: DriveFlowFixtures.sinceCleared)
        let reading = tracker.record(2, for: DriveFlowFixtures.sinceCleared)
        XCTAssertEqual(reading, DistanceTracker.Reading(source: .distanceSinceCodesCleared, startKilometers: 2, endKilometers: 2))
    }

    func testNonDistanceRequestIsIgnored() {
        var tracker = DistanceTracker()
        XCTAssertNil(tracker.record(3000, for: DriveFlowFixtures.rpm))
        XCTAssertNil(tracker.current)
    }
}
