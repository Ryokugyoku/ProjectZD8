import XCTest
@testable import ProjectZD8

@MainActor
final class LogHistoryModelTests: XCTestCase {
    private struct Harness {
        let model: LogHistoryModel
        let sessions: RecordsFakeSessionRepository
        let vehicles: RecordsFakeVehicleRepository
        let changes: RecordsFakeStoreChanges
    }

    private func makeHarness(vehicles: [Vehicle], sessions: [DriveSession]) -> Harness {
        let sessionRepo = RecordsFakeSessionRepository(sessions: sessions)
        let vehicleRepo = RecordsFakeVehicleRepository(vehicles: vehicles)
        let changes = RecordsFakeStoreChanges()
        return Harness(
            model: LogHistoryModel(sessions: sessionRepo, vehicles: vehicleRepo, changes: changes),
            sessions: sessionRepo, vehicles: vehicleRepo, changes: changes
        )
    }

    func testStartedGroupsByVehicleAndSeparatesRecording() async {
        let car = RecordsFixtures.vehicle(name: "Car")
        let t = RecordsFixtures.referenceDate
        let h = makeHarness(vehicles: [car], sessions: [
            RecordsFixtures.session(vehicleID: car.id, startedAt: t, duration: 100),
            RecordsFixtures.session(vehicleID: car.id, startedAt: t.addingTimeInterval(1000), duration: nil)
        ])
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.loadPhase, .loaded)
        XCTAssertEqual(h.model.state.activeSessions.count, 1)
        XCTAssertEqual(h.model.state.groups.count, 1)
        XCTAssertEqual(h.model.state.groups[0].vehicleName, "Car")
        XCTAssertEqual(h.model.state.groups[0].sessionCount, 1)
        XCTAssertEqual(h.model.state.totalFinishedCount, 1)
        XCTAssertEqual(h.changes.requestedAreas.first, [.sessions, .vehicles])
    }

    func testFilterSortAndReset() async {
        let car = RecordsFixtures.vehicle()
        let t = RecordsFixtures.referenceDate
        let h = makeHarness(vehicles: [car], sessions: [
            RecordsFixtures.session(vehicleID: car.id, startedAt: t, duration: 100, isDemo: true),
            RecordsFixtures.session(vehicleID: car.id, startedAt: t.addingTimeInterval(1000), duration: 500)
        ])
        await h.model.perform(.started)
        await h.model.perform(.filterChanged(LogHistoryFilter(dataKind: .demo)))
        XCTAssertEqual(h.model.state.visibleCount, 1)
        XCTAssertTrue(h.model.state.hasActiveFilters)
        await h.model.perform(.filterChanged(LogHistoryFilter(endReason: .appTerminated)))
        XCTAssertTrue(h.model.state.isFilteredEmpty)
        await h.model.perform(.filterReset)
        XCTAssertEqual(h.model.state.visibleCount, 2)
        await h.model.perform(.sortOrderChanged(.longestDuration))
        XCTAssertEqual(h.model.state.groups[0].sessions.compactMap(\.duration), [500, 100])
    }

    func testDetailExposesAttributesRawLocationAndUploadState() async throws {
        let car = RecordsFixtures.vehicle(name: "Car")
        let local = RecordsFixtures.session(vehicleID: car.id, odometerStart: 100, odometerEnd: 112.5, sampleCount: 10, respondedCount: 8)
        let cloud = RecordsFixtures.session(vehicleID: car.id, startedAt: RecordsFixtures.referenceDate.addingTimeInterval(9000), rawAvailability: .cloudOnly, archiveDigest: "abc")
        let h = makeHarness(vehicles: [car], sessions: [local, cloud])
        await h.model.perform(.started)
        await h.model.perform(.detailRequested(local.id))
        let detail = try XCTUnwrap(h.model.state.detail)
        XCTAssertEqual(detail.vehicleName, "Car")
        XCTAssertEqual(detail.row.distanceKilometers, 12.5)
        XCTAssertEqual(detail.noResponseCount, 2)
        XCTAssertEqual(detail.responseRate, 0.8)
        XCTAssertEqual(detail.row.rawLocation, .onThisDevice)
        XCTAssertEqual(detail.row.uploadState, .notUploaded)
        XCTAssertFalse(detail.row.canFreeUpSpace)
        XCTAssertEqual(detail.adapterTransportKey, "history.detail.transport.bluetoothLowEnergy")
        XCTAssertEqual(detail.distanceSourceKey, "history.detail.distance_source.odometer")
        await h.model.perform(.detailRequested(cloud.id))
        XCTAssertEqual(h.model.state.detail?.row.rawLocation, .iCloudOnly)
        XCTAssertEqual(h.model.state.detail?.row.uploadState, .uploaded)
        XCTAssertEqual(h.model.state.detail?.archiveDigest, "abc")
        await h.model.perform(.detailClosed)
        XCTAssertNil(h.model.state.detail)
    }

    func testDetailForUnknownSessionFails() async {
        let h = makeHarness(vehicles: [], sessions: [])
        await h.model.perform(.detailRequested(SessionID()))
        XCTAssertEqual(h.model.state.failure, .sessionNotFound)
    }

    func testZeroSampleSessionHasNoResponseRate() async throws {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id, sampleCount: 0, respondedCount: 0)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.detailRequested(s.id))
        XCTAssertNil(h.model.state.detail?.responseRate)
    }

    func testDeleteConfirmFlow() async {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.detailRequested(s.id))
        await h.model.perform(.deleteRequested(s.id))
        XCTAssertEqual(h.model.state.pendingDeletion?.sessionID, s.id)
        XCTAssertTrue(h.sessions.deletedIDs.isEmpty)
        await h.model.perform(.deleteCancelled)
        XCTAssertNil(h.model.state.pendingDeletion)
        await h.model.perform(.deleteRequested(s.id))
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.sessions.deletedIDs, [s.id])
        XCTAssertNil(h.model.state.detail)
        XCTAssertEqual(h.model.state.totalFinishedCount, 0)
    }

    func testDeleteRefusedForRecordingSession() async {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id, duration: nil)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.deleteRequested(s.id))
        XCTAssertEqual(h.model.state.failure, .deleteRefusedWhileRecording)
        XCTAssertNil(h.model.state.pendingDeletion)
        XCTAssertTrue(h.sessions.deletedIDs.isEmpty)
    }

    func testDeleteFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.deleteRequested(s.id))
        h.sessions.setDeleteError(.ioFailure)
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.model.state.failure, .deleteFailed)
    }

    func testFreeUpSpaceOnlyWhenUploaded() async {
        let car = RecordsFixtures.vehicle()
        let notUploaded = RecordsFixtures.session(vehicleID: car.id)
        let uploaded = RecordsFixtures.session(vehicleID: car.id, startedAt: RecordsFixtures.referenceDate.addingTimeInterval(5000), archiveDigest: "sha")
        let h = makeHarness(vehicles: [car], sessions: [notUploaded, uploaded])
        await h.model.perform(.started)
        await h.model.perform(.freeUpSpaceRequested(notUploaded.id))
        XCTAssertEqual(h.model.state.failure, .freeUpSpaceNotAllowed)
        XCTAssertNil(h.model.state.pendingFreeUp)
        h.model.send(.failureDismissed)

        await h.model.perform(.freeUpSpaceRequested(uploaded.id))
        XCTAssertEqual(h.model.state.pendingFreeUp?.sessionID, uploaded.id)
        await h.model.perform(.freeUpSpaceConfirmed)
        XCTAssertEqual(h.sessions.evictedIDs, [uploaded.id])
        XCTAssertNil(h.model.state.failure)
        let row = h.model.state.groups.flatMap(\.sessions).first { $0.id == uploaded.id }
        XCTAssertEqual(row?.rawLocation, .iCloudOnly)
        XCTAssertEqual(row?.canFreeUpSpace, false)
    }

    func testFreeUpSpaceRaceWithRepositoryRefusalIsTyped() async {
        let car = RecordsFixtures.vehicle()
        let uploaded = RecordsFixtures.session(vehicleID: car.id, archiveDigest: "sha")
        let h = makeHarness(vehicles: [car], sessions: [uploaded])
        await h.model.perform(.started)
        await h.model.perform(.freeUpSpaceRequested(uploaded.id))
        h.sessions.setEvictError(.invalidState)
        await h.model.perform(.freeUpSpaceConfirmed)
        XCTAssertEqual(h.model.state.failure, .freeUpSpaceNotAllowed)
        h.model.send(.failureDismissed)
        await h.model.perform(.freeUpSpaceRequested(uploaded.id))
        h.sessions.setEvictError(.ioFailure)
        await h.model.perform(.freeUpSpaceConfirmed)
        XCTAssertEqual(h.model.state.failure, .freeUpSpaceFailed)
    }

    func testAnalysisRequestIsExposedUntilHandled() async {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.analysisRequested(s.id))
        XCTAssertEqual(h.model.state.analysisRequest, s.id)
        await h.model.perform(.analysisRequestHandled)
        XCTAssertNil(h.model.state.analysisRequest)
        await h.model.perform(.analysisRequested(SessionID()))
        XCTAssertNil(h.model.state.analysisRequest)
        XCTAssertEqual(h.model.state.failure, .sessionNotFound)
    }

    func testLoadFailureIsReported() async {
        let h = makeHarness(vehicles: [], sessions: [])
        h.sessions.setListError(.ioFailure)
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.failure, .loadFailed)
    }

    func testStoreChangeRefreshesAndKeepsOpenDetailCurrent() async {
        let car = RecordsFixtures.vehicle()
        let s = RecordsFixtures.session(vehicleID: car.id, duration: nil)
        let h = makeHarness(vehicles: [car], sessions: [s])
        await h.model.perform(.started)
        await h.model.perform(.detailRequested(s.id))
        XCTAssertEqual(h.model.state.detail?.row.isRecording, true)
        var ended = s
        ended.endedAt = s.startedAt.addingTimeInterval(60)
        ended.endReason = .userStopped
        h.sessions.replace([ended])
        h.changes.emit()
        let refreshed = await recordsEventually { h.model.state.detail?.row.isRecording == false }
        XCTAssertTrue(refreshed)
        XCTAssertTrue(h.model.state.activeSessions.isEmpty)
        XCTAssertEqual(h.model.state.groups.first?.sessionCount, 1)
        h.model.send(.stopped)
    }
}
