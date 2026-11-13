import XCTest
@testable import ProjectZD8

@MainActor
final class MaintenanceModelTests: XCTestCase {
    private struct Harness {
        let model: MaintenanceModel
        let vehicles: RecordsFakeVehicleRepository
        let maintenance: RecordsFakeMaintenanceRepository
        let photos: RecordsFakePhotoRepository
        let changes: RecordsFakeStoreChanges
    }

    private let stamp = RecordsFixtures.referenceDate.addingTimeInterval(500)

    private func makeHarness(
        vehicles: [Vehicle],
        records: [MaintenanceRecord] = [],
        photos: [PhotoID: Data] = [:]
    ) -> Harness {
        let vehicleRepo = RecordsFakeVehicleRepository(vehicles: vehicles)
        let maintenanceRepo = RecordsFakeMaintenanceRepository(records: records)
        let photoRepo = RecordsFakePhotoRepository(images: photos)
        let changes = RecordsFakeStoreChanges()
        let stamp = stamp
        let model = MaintenanceModel(vehicles: vehicleRepo, maintenance: maintenanceRepo, photos: photoRepo, changes: changes, now: { stamp })
        return Harness(model: model, vehicles: vehicleRepo, maintenance: maintenanceRepo, photos: photoRepo, changes: changes)
    }

    func testStartedSelectsFirstVehicleAndListsNewestFirst() async {
        let a = RecordsFixtures.vehicle(name: "A")
        let b = RecordsFixtures.vehicle(name: "B")
        let t = RecordsFixtures.referenceDate
        let h = makeHarness(vehicles: [b, a], records: [
            RecordsFixtures.maintenance(vehicleID: a.id, title: "old", performedAt: t),
            RecordsFixtures.maintenance(vehicleID: a.id, kind: .heavy, title: "new", performedAt: t.addingTimeInterval(100)),
            RecordsFixtures.maintenance(vehicleID: b.id, title: "other")
        ])
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.selectedVehicleID, a.id)
        XCTAssertEqual(h.model.state.rows.map(\.title), ["new", "old"])
        XCTAssertEqual(h.model.state.lightCount, 1)
        XCTAssertEqual(h.model.state.heavyCount, 1)
        await h.model.perform(.kindFilterChanged(.heavy))
        XCTAssertEqual(h.model.state.visibleRows.map(\.title), ["new"])
        await h.model.perform(.vehicleSelected(b.id))
        XCTAssertEqual(h.model.state.rows.map(\.title), ["other"])
    }

    func testLoadFailureIsReported() async {
        let h = makeHarness(vehicles: [RecordsFixtures.vehicle()])
        h.maintenance.setError(.ioFailure)
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.failure, .loadFailed)
    }

    func testCreateWithoutVehicleFails() async {
        let h = makeHarness(vehicles: [])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.light))
        XCTAssertEqual(h.model.state.failure, .vehicleRequired)
        XCTAssertNil(h.model.state.editor)
    }

    func testCreateEditSaveSetsModifiedAtAndRefreshesList() async throws {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.light))
        XCTAssertEqual(h.model.state.editor?.isNew, true)
        XCTAssertEqual(h.model.state.editor?.issues, [.titleRequired])
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.model.state.failure, .invalidInput)
        XCTAssertTrue(h.maintenance.stored.isEmpty)
        h.model.send(.failureDismissed)

        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.title = "Oil change"
        draft.odometerKilometers = 1000
        await h.model.perform(.draftChanged(draft))
        XCTAssertEqual(h.model.state.editor?.issues, [])
        await h.model.perform(.saveRequested)
        XCTAssertNil(h.model.state.editor)
        let saved = try XCTUnwrap(h.maintenance.stored.first)
        XCTAssertEqual(saved.modifiedAt, stamp)
        XCTAssertEqual(saved.vehicleID, car.id)
        XCTAssertEqual(h.model.state.rows.map(\.title), ["Oil change"])
        XCTAssertNotNil(h.model.state.rows.first?.odometerText)
    }

    func testSaveFailureKeepsEditor() async throws {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.light))
        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.title = "x"
        await h.model.perform(.draftChanged(draft))
        h.maintenance.setSaveError(.ioFailure)
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.model.state.failure, .saveFailed)
        XCTAssertNotNil(h.model.state.editor)
        XCTAssertEqual(h.model.state.editor?.isSaving, false)
    }

    func testPhotoPickedAddsPhotoAndCancelDeletesNewOnly() async throws {
        let car = RecordsFixtures.vehicle()
        let existing = PhotoID()
        let record = RecordsFixtures.maintenance(vehicleID: car.id, photos: [MaintenancePhoto(id: existing, caption: "before")])
        let h = makeHarness(vehicles: [car], records: [record], photos: [existing: Data([5])])
        await h.model.perform(.started)
        await h.model.perform(.editRequested(record.id))
        XCTAssertEqual(h.model.state.editor?.photoData[existing], Data([5]))
        await h.model.perform(.photoPicked(Data([1, 2])))
        XCTAssertEqual(h.model.state.editor?.draft.photos.count, 2)
        let added = try XCTUnwrap(h.model.state.editor?.draft.photos.last?.id)
        XCTAssertEqual(h.model.state.editor?.photoData[added], Data([1, 2]))
        await h.model.perform(.photoCaptionChanged(added, "after"))
        XCTAssertEqual(h.model.state.editor?.draft.photos.last?.caption, "after")
        await h.model.perform(.editCancelled)
        XCTAssertEqual(h.photos.deletedIDs, [added])
        XCTAssertTrue(h.photos.storedIDs.contains(existing))
    }

    func testRemovingOriginalPhotoDeletesItOnSaveOnly() async {
        let car = RecordsFixtures.vehicle()
        let existing = PhotoID()
        let record = RecordsFixtures.maintenance(vehicleID: car.id, photos: [MaintenancePhoto(id: existing)])
        let h = makeHarness(vehicles: [car], records: [record], photos: [existing: Data([5])])
        await h.model.perform(.started)
        await h.model.perform(.editRequested(record.id))
        await h.model.perform(.photoRemoved(existing))
        XCTAssertTrue(h.photos.deletedIDs.isEmpty)
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.photos.deletedIDs, [existing])
        XCTAssertTrue(h.maintenance.stored.first?.photos.isEmpty == true)
    }

    func testRemovingNewPhotoDeletesImmediately() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.light))
        await h.model.perform(.photoPicked(Data([1])))
        guard let id = h.model.state.editor?.draft.photos.first?.id else { return XCTFail("photo not added") }
        await h.model.perform(.photoRemoved(id))
        XCTAssertEqual(h.photos.deletedIDs, [id])
        XCTAssertTrue(h.model.state.editor?.draft.photos.isEmpty == true)
    }

    func testPhotoSaveFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.light))
        h.photos.setSaveError(.ioFailure)
        await h.model.perform(.photoPicked(Data([1])))
        XCTAssertEqual(h.model.state.failure, .photoFailed)
        XCTAssertTrue(h.model.state.editor?.draft.photos.isEmpty == true)
    }

    func testHeavyEditingActionsViaModel() async throws {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        await h.model.perform(.createRequested(.heavy))
        await h.model.perform(.fastenerGroupAdded)
        let groupID = try XCTUnwrap(h.model.state.editor?.draft.fastenerGroups.first?.id)
        await h.model.perform(.fastenerAdded(groupID: groupID))
        let evidenceID = try XCTUnwrap(h.model.state.editor?.draft.fastenerGroups.first?.installations.first?.id)
        await h.model.perform(.fastenerConfirmed(groupID: groupID, evidenceID: evidenceID))
        XCTAssertEqual(h.model.state.editor?.draft.fastenerGroups[0].installations[0].tightenedAt, stamp)
        await h.model.perform(.photoPicked(Data([1])))
        let photoID = try XCTUnwrap(h.model.state.editor?.draft.photos.first?.id)
        await h.model.perform(.fastenerPhotoLinked(groupID: groupID, evidenceID: evidenceID, photoID: photoID))
        XCTAssertEqual(h.model.state.editor?.draft.fastenerGroups[0].installations[0].photoIDs, [photoID])
        await h.model.perform(.workItemAdded)
        XCTAssertEqual(h.model.state.editor?.draft.workItems.count, 2)
        XCTAssertEqual(h.model.state.editor?.issues, [.titleRequired, .fastenerGroupNameRequired(groupID)])
    }

    func testDeleteRequiresConfirmation() async {
        let car = RecordsFixtures.vehicle()
        let record = RecordsFixtures.maintenance(vehicleID: car.id, title: "Tires")
        let h = makeHarness(vehicles: [car], records: [record])
        await h.model.perform(.started)
        await h.model.perform(.deleteRequested(record.id))
        XCTAssertEqual(h.model.state.pendingDeletion?.title, "Tires")
        XCTAssertEqual(h.maintenance.stored.count, 1)
        await h.model.perform(.deleteCancelled)
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.maintenance.stored.count, 1)
        await h.model.perform(.deleteRequested(record.id))
        await h.model.perform(.deleteConfirmed)
        XCTAssertTrue(h.maintenance.stored.isEmpty)
        XCTAssertTrue(h.model.state.rows.isEmpty)
    }

    func testDeleteFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let record = RecordsFixtures.maintenance(vehicleID: car.id)
        let h = makeHarness(vehicles: [car], records: [record])
        await h.model.perform(.started)
        await h.model.perform(.deleteRequested(record.id))
        h.maintenance.setError(.ioFailure)
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.model.state.failure, .deleteFailed)
    }

    func testStoreChangeRefreshesListButNotOpenEditor() async throws {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.started)
        XCTAssertEqual(h.changes.requestedAreas.first, [.vehicles, .maintenance, .photos])
        await h.model.perform(.createRequested(.light))
        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.title = "typing"
        await h.model.perform(.draftChanged(draft))
        h.maintenance.replace([RecordsFixtures.maintenance(vehicleID: car.id, title: "synced")])
        h.changes.emit()
        let refreshed = await recordsEventually { h.model.state.rows.map(\.title) == ["synced"] }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(h.model.state.editor?.draft.title, "typing")
        h.model.send(.stopped)
    }

    func testLocalizationKeysCoverAllCases() {
        XCTAssertEqual(Set(MaintenanceComponent.allCases.map(\.localizationKey)).count, MaintenanceComponent.allCases.count)
        XCTAssertEqual(Set(MaintenanceOperation.allCases.map(\.localizationKey)).count, MaintenanceOperation.allCases.count)
        XCTAssertEqual(MaintenanceKind.light.localizationKey, "maintenance.kind.light")
        XCTAssertEqual(MaintenanceKind.heavy.hintLocalizationKey, "maintenance.kind.heavy.hint")
    }
}
