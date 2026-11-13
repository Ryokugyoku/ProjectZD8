import XCTest
@testable import ProjectZD8

final class LoadVehicleActivitySummariesUseCaseTests: XCTestCase {
    func testAggregatesPerVehicle() async throws {
        let a = VehicleID()
        let b = VehicleID()
        let t0 = RecordsFixtures.referenceDate
        let repo = RecordsFakeSessionRepository(sessions: [
            RecordsFixtures.session(vehicleID: a, startedAt: t0, duration: 600, odometerEnd: 100),
            RecordsFixtures.session(vehicleID: a, startedAt: t0.addingTimeInterval(10_000), duration: 300, endReason: .connectionLost, odometerEnd: 150),
            RecordsFixtures.session(vehicleID: a, startedAt: t0.addingTimeInterval(20_000), duration: nil, odometerStart: 150),
            RecordsFixtures.session(vehicleID: b, startedAt: t0, duration: 60)
        ])
        let result = try await LoadVehicleActivitySummariesUseCase(sessions: repo).execute()
        let summary = try XCTUnwrap(result[a])
        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(summary.totalRecordedDuration, 900)
        XCTAssertEqual(summary.interruptedCount, 1)
        XCTAssertTrue(summary.isRecording)
        XCTAssertEqual(summary.latestOdometerKilometers, 150)
        XCTAssertEqual(summary.lastLoggedAt, t0.addingTimeInterval(20_000))
        XCTAssertEqual(result[b]?.sessionCount, 1)
        XCTAssertEqual(result[b]?.isRecording, false)
        XCTAssertNil(result[b]?.latestOdometerKilometers)
        XCTAssertNil(result[VehicleID()])
    }

    func testLoadErrorPropagates() async {
        let repo = RecordsFakeSessionRepository()
        repo.setListError(.ioFailure)
        do {
            _ = try await LoadVehicleActivitySummariesUseCase(sessions: repo).execute()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? StoreError, .ioFailure)
        }
    }
}
