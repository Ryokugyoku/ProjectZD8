import XCTest
@testable import ProjectZD8

@MainActor
final class VehicleManagementModelTests: XCTestCase {
    private struct Harness {
        let model: VehicleManagementModel
        let vehicles: RecordsFakeVehicleRepository
        let sessions: RecordsFakeSessionRepository
        let pids: RecordsFakePIDSettingRepository
        let photos: RecordsFakePhotoRepository
        let changes: RecordsFakeStoreChanges
    }

    private func makeHarness(
        vehicles: [Vehicle] = [],
        sessions: [DriveSession] = [],
        pidSettings: [VehiclePIDSetting] = [],
        photos: [PhotoID: Data] = [:]
    ) -> Harness {
        let vehicleRepo = RecordsFakeVehicleRepository(vehicles: vehicles)
        let sessionRepo = RecordsFakeSessionRepository(sessions: sessions)
        let pidRepo = RecordsFakePIDSettingRepository(settings: pidSettings)
        let photoRepo = RecordsFakePhotoRepository(images: photos)
        let changes = RecordsFakeStoreChanges()
        let model = VehicleManagementModel(
            vehicles: vehicleRepo, sessions: sessionRepo, pidSettings: pidRepo, photos: photoRepo, changes: changes,
            now: { RecordsFixtures.referenceDate.addingTimeInterval(1000) }
        )
        return Harness(model: model, vehicles: vehicleRepo, sessions: sessionRepo, pids: pidRepo, photos: photoRepo, changes: changes)
    }

    func testStartedLoadsVehiclesWithActivityAndPhoto() async {
        let photoID = PhotoID()
        let car = RecordsFixtures.vehicle(name: "A", photoID: photoID)
        let h = makeHarness(
            vehicles: [car],
            sessions: [RecordsFixtures.session(vehicleID: car.id, duration: 600, odometerEnd: 1234)],
            photos: [photoID: Data([1, 2, 3])]
        )
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.loadPhase, .loaded)
        let item = try? XCTUnwrap(h.model.state.vehicles.first)
        XCTAssertEqual(item?.activity.sessionCount, 1)
        XCTAssertEqual(item?.activity.latestOdometerKilometers, 1234)
        XCTAssertEqual(item?.photoData, Data([1, 2, 3]))
        XCTAssertNil(h.model.state.failure)
    }

    func testLoadFailureIsReportedNotHidden() async {
        let h = makeHarness()
        h.vehicles.setError(.ioFailure)
        await h.model.perform(.started)
        XCTAssertEqual(h.model.state.failure, .loadFailed)
        XCTAssertTrue(h.model.state.vehicles.isEmpty)
    }

    func testPhotoReadFailureIsReported() async {
        let photoID = PhotoID()
        let h = makeHarness(vehicles: [RecordsFixtures.vehicle(photoID: photoID)], photos: [photoID: Data([1])])
        h.photos.setReadError(.ioFailure)
        await h.model.perform(.refreshRequested)
        XCTAssertEqual(h.model.state.failure, .photoLoadFailed)
        XCTAssertEqual(h.model.state.vehicles.count, 1)
    }

    func testStoreChangeRefreshesAutomaticallyAndSubscribesToRelevantAreas() async {
        let h = makeHarness(vehicles: [RecordsFixtures.vehicle(name: "A")])
        await h.model.perform(.started)
        XCTAssertEqual(h.changes.requestedAreas.first, [.vehicles, .sessions, .photos, .pidSettings])
        h.vehicles.replace([RecordsFixtures.vehicle(name: "A"), RecordsFixtures.vehicle(name: "B")])
        h.changes.emit()
        let refreshed = await recordsEventually { h.model.state.vehicles.count == 2 }
        XCTAssertTrue(refreshed)
        h.model.send(.stopped)
    }

    func testEditingNormalizesEnergySourcesWhenPowertrainChanges() async throws {
        let car = RecordsFixtures.vehicle(powertrain: .combustion, energySources: [.gasolineRegular])
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.powertrain = .batteryElectric
        await h.model.perform(.draftChanged(draft))
        XCTAssertEqual(h.model.state.editor?.draft.energySources, [.electricity])
        XCTAssertEqual(h.model.state.editor?.draft.energySourceOptions.map(\.source), [.electricity])
    }

    func testSaveRejectsInvalidDraftWithoutWriting() async throws {
        let car = RecordsFixtures.vehicle(name: "Keep")
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.name = "  "
        draft.tankCapacityLiters = -1
        draft.modelYear = 1800
        await h.model.perform(.draftChanged(draft))
        XCTAssertEqual(Set(h.model.state.editor?.issues ?? []), [.nameRequired, .tankCapacityInvalid, .modelYearInvalid])
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.model.state.failure, .invalidInput)
        XCTAssertNotNil(h.model.state.editor)
        XCTAssertEqual(h.vehicles.stored.first?.name, "Keep")
    }

    func testSaveWritesTrimmedValuesAndModifiedAt() async throws {
        let car = RecordsFixtures.vehicle(name: "Old")
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        var draft = try XCTUnwrap(h.model.state.editor?.draft)
        draft.name = "  New  "
        draft.tankCapacityLiters = 50
        draft.modelYear = 2020
        await h.model.perform(.draftChanged(draft))
        await h.model.perform(.saveRequested)
        XCTAssertNil(h.model.state.editor)
        let saved = try XCTUnwrap(h.vehicles.stored.first)
        XCTAssertEqual(saved.name, "New")
        XCTAssertEqual(saved.tankCapacityLiters, 50)
        XCTAssertEqual(saved.modifiedAt, RecordsFixtures.referenceDate.addingTimeInterval(1000))
        XCTAssertEqual(h.model.state.vehicles.first?.vehicle.name, "New")
    }

    func testSaveFailureKeepsEditorOpen() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        h.vehicles.setError(.ioFailure)
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.model.state.failure, .saveFailed)
        XCTAssertEqual(h.model.state.editor?.isSaving, false)
    }

    func testPhotoPickedStoresImageAndSaveDeletesReplacedOriginal() async throws {
        let original = PhotoID()
        let car = RecordsFixtures.vehicle(photoID: original)
        let h = makeHarness(vehicles: [car], photos: [original: Data([9])])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        await h.model.perform(.photoPicked(Data([7, 7])))
        let newID = try XCTUnwrap(h.model.state.editor?.draft.photoID)
        XCTAssertNotEqual(newID, original)
        XCTAssertEqual(h.model.state.editor?.photoData, Data([7, 7]))
        await h.model.perform(.saveRequested)
        XCTAssertEqual(h.vehicles.stored.first?.photoID, newID)
        XCTAssertEqual(h.photos.deletedIDs, [original])
        XCTAssertEqual(h.model.state.vehicles.first?.photoData, Data([7, 7]))
    }

    func testSecondPickAndCancelCleanUpUnsavedPhotos() async throws {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        await h.model.perform(.photoPicked(Data([1])))
        let first = try XCTUnwrap(h.model.state.editor?.draft.photoID)
        await h.model.perform(.photoPicked(Data([2])))
        let second = try XCTUnwrap(h.model.state.editor?.draft.photoID)
        XCTAssertEqual(h.photos.deletedIDs, [first])
        await h.model.perform(.editCancelled)
        XCTAssertNil(h.model.state.editor)
        XCTAssertEqual(h.photos.deletedIDs, [first, second])
        XCTAssertNil(h.vehicles.stored.first?.photoID)
    }

    func testPhotoRemovedDropsPhotoOnSave() async {
        let original = PhotoID()
        let car = RecordsFixtures.vehicle(photoID: original)
        let h = makeHarness(vehicles: [car], photos: [original: Data([9])])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        await h.model.perform(.photoRemoved)
        XCTAssertNil(h.model.state.editor?.draft.photoID)
        XCTAssertTrue(h.photos.deletedIDs.isEmpty, "saved photo is only removed when the edit is saved")
        await h.model.perform(.saveRequested)
        XCTAssertNil(h.vehicles.stored.first?.photoID)
        XCTAssertEqual(h.photos.deletedIDs, [original])
    }

    func testPhotoSaveFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.editRequested(car.id))
        h.photos.setSaveError(.ioFailure)
        await h.model.perform(.photoPicked(Data([1])))
        XCTAssertEqual(h.model.state.failure, .photoFailed)
        XCTAssertNil(h.model.state.editor?.draft.photoID)
    }

    func testDeletionRequiresConfirmationAndRemovesVehicle() async {
        let car = RecordsFixtures.vehicle(name: "Gone")
        let h = makeHarness(vehicles: [car], sessions: [RecordsFixtures.session(vehicleID: car.id)])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.deleteRequested(car.id))
        XCTAssertEqual(h.model.state.pendingDeletion, VehicleDeletionPrompt(vehicleID: car.id, vehicleName: "Gone", sessionCount: 1))
        XCTAssertTrue(h.vehicles.deletedIDs.isEmpty)
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.vehicles.deletedIDs, [car.id])
        XCTAssertNil(h.model.state.pendingDeletion)
        XCTAssertTrue(h.model.state.vehicles.isEmpty)
    }

    func testDeletionCanBeCancelled() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.deleteRequested(car.id))
        await h.model.perform(.deleteCancelled)
        await h.model.perform(.deleteConfirmed)
        XCTAssertTrue(h.vehicles.deletedIDs.isEmpty)
    }

    func testDeletionRefusedWhileRecording() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car], sessions: [RecordsFixtures.session(vehicleID: car.id, duration: nil)])
        await h.model.perform(.refreshRequested)
        XCTAssertTrue(h.model.state.vehicles.first?.activity.isRecording == true)
        await h.model.perform(.deleteRequested(car.id))
        XCTAssertEqual(h.model.state.failure, .deleteRefusedWhileRecording)
        XCTAssertNil(h.model.state.pendingDeletion)
        XCTAssertTrue(h.vehicles.deletedIDs.isEmpty)
    }

    func testDeletionRefusedWhenRecordingStartedAfterPrompt() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.deleteRequested(car.id))
        h.sessions.replace([RecordsFixtures.session(vehicleID: car.id, duration: nil)])
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.model.state.failure, .deleteRefusedWhileRecording)
        XCTAssertTrue(h.vehicles.deletedIDs.isEmpty)
    }

    func testDeleteFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.deleteRequested(car.id))
        h.vehicles.setError(.ioFailure)
        await h.model.perform(.deleteConfirmed)
        XCTAssertEqual(h.model.state.failure, .deleteFailed)
    }

    func testPIDSettingsJoinFilterAndToggle() async throws {
        let zd8 = RecordsFixtures.vehicle(name: "ZD8", vin: "JF1ZD8AAAAA000001")
        let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let odo = OBDPIDRequest(service: 0x21, pid: 0x02)
        let now = RecordsFixtures.referenceDate
        let h = makeHarness(vehicles: [zd8], pidSettings: [
            VehiclePIDSetting(vehicleID: zd8.id, request: rpm, isSupported: true, isCollectionEnabled: true, discoveredAt: now),
            VehiclePIDSetting(vehicleID: zd8.id, request: speed, isSupported: false, isCollectionEnabled: true, discoveredAt: now),
            VehiclePIDSetting(vehicleID: zd8.id, request: odo, isSupported: true, isCollectionEnabled: false, discoveredAt: now)
        ])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.pidSettingsRequested(zd8.id))
        let settings = try XCTUnwrap(h.model.state.pidSettings)
        XCTAssertEqual(settings.items.first { $0.request == rpm }?.support, .supported)
        XCTAssertEqual(settings.items.first { $0.request == speed }?.support, .unsupported)
        XCTAssertEqual(settings.items.first { $0.request == odo }?.isVehicleSpecific, true)
        XCTAssertEqual(settings.items.first { $0.request == odo }?.isEnabled, false)
        XCTAssertTrue(settings.hasVehicleSpecificItems)

        await h.model.perform(.pidCategoryFilterChanged(.vehicleSpecific))
        XCTAssertTrue(h.model.state.pidSettings?.visibleItems.allSatisfy(\.isVehicleSpecific) == true)
        await h.model.perform(.pidCategoryFilterChanged(.category(.engine)))
        XCTAssertTrue(h.model.state.pidSettings?.visibleItems.contains { $0.request == rpm } == true)
        await h.model.perform(.pidCategoryFilterChanged(.all))
        await h.model.perform(.pidEnabledFilterChanged(.enabled))
        XCTAssertEqual(h.model.state.pidSettings?.visibleItems.map(\.request), [rpm])

        await h.model.perform(.pidCollectionToggled(odo, isEnabled: true))
        XCTAssertEqual(h.pids.stored.first { $0.request == odo }?.isCollectionEnabled, true)
        XCTAssertEqual(h.model.state.pidSettings?.items.first { $0.request == odo }?.isEnabled, true)
    }

    func testStandardVehicleHasNoVehicleSpecificPIDsAndUnsupportedToggleIsRefused() async {
        let car = RecordsFixtures.vehicle(vin: "OTHERVIN000000001")
        let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
        let h = makeHarness(vehicles: [car], pidSettings: [
            VehiclePIDSetting(vehicleID: car.id, request: speed, isSupported: false, isCollectionEnabled: false, discoveredAt: RecordsFixtures.referenceDate)
        ])
        await h.model.perform(.refreshRequested)
        await h.model.perform(.pidSettingsRequested(car.id))
        XCTAssertEqual(h.model.state.pidSettings?.hasVehicleSpecificItems, false)
        await h.model.perform(.pidCollectionToggled(speed, isEnabled: true))
        XCTAssertEqual(h.model.state.failure, .pidNotSupported)
        XCTAssertEqual(h.pids.stored.first?.isCollectionEnabled, false)
    }

    func testPIDSettingsLoadFailureIsReported() async {
        let car = RecordsFixtures.vehicle()
        let h = makeHarness(vehicles: [car])
        await h.model.perform(.refreshRequested)
        h.pids.setError(.ioFailure)
        await h.model.perform(.pidSettingsRequested(car.id))
        XCTAssertEqual(h.model.state.failure, .pidSettingsFailed)
        XCTAssertNil(h.model.state.pidSettings)
    }

    func testFailureCanBeDismissed() async {
        let h = makeHarness()
        await h.model.perform(.editRequested(VehicleID()))
        XCTAssertEqual(h.model.state.failure, .vehicleNotFound)
        h.model.send(.failureDismissed)
        XCTAssertNil(h.model.state.failure)
    }
}
