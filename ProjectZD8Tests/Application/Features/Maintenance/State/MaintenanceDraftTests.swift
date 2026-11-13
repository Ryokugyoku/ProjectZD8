import XCTest
@testable import ProjectZD8

final class MaintenanceDraftTests: XCTestCase {
    private let now = RecordsFixtures.referenceDate

    func testNewDraftHasKindSpecificDefaultWorkItem() {
        let light = MaintenanceDraft(vehicleID: VehicleID(), kind: .light, now: now)
        XCTAssertEqual(light.workItems.map(\.component), [.engineOil])
        XCTAssertEqual(light.workItems.map(\.operation), [.replacement])
        let heavy = MaintenanceDraft(vehicleID: VehicleID(), kind: .heavy, now: now)
        XCTAssertEqual(heavy.workItems.map(\.component), [.engineAssembly])
        XCTAssertEqual(heavy.workItems.map(\.operation), [.inspection])
    }

    func testFastenerGroupsOnlyForHeavy() {
        var light = MaintenanceDraft(vehicleID: VehicleID(), kind: .light, now: now)
        light.addFastenerGroup()
        XCTAssertTrue(light.fastenerGroups.isEmpty)
        var heavy = MaintenanceDraft(vehicleID: VehicleID(), kind: .heavy, now: now)
        heavy.addFastenerGroup()
        XCTAssertEqual(heavy.fastenerGroups.count, 1)
    }

    func testFastenerConfirmLinkAndPhotoRemovalCascade() throws {
        var draft = MaintenanceDraft(vehicleID: VehicleID(), kind: .heavy, now: now)
        draft.addFastenerGroup()
        let groupID = try XCTUnwrap(draft.fastenerGroups.first?.id)
        draft.addFastener(to: groupID)
        let evidenceID = try XCTUnwrap(draft.fastenerGroups.first?.installations.first?.id)
        let photo = PhotoID()
        draft.linkPhoto(photo, groupID: groupID, evidenceID: evidenceID)
        XCTAssertTrue(draft.fastenerGroups[0].installations[0].photoIDs.isEmpty, "unknown photos cannot be linked")
        draft.addPhoto(MaintenancePhoto(id: photo, capturedAt: now))
        draft.linkPhoto(photo, groupID: groupID, evidenceID: evidenceID)
        draft.linkPhoto(photo, groupID: groupID, evidenceID: evidenceID)
        draft.linkRemovalPhoto(photo, groupID: groupID)
        XCTAssertEqual(draft.fastenerGroups[0].installations[0].photoIDs, [photo])
        XCTAssertEqual(draft.fastenerGroups[0].removalPhotoIDs, [photo])
        draft.confirmFastener(groupID: groupID, evidenceID: evidenceID, at: now)
        XCTAssertEqual(draft.fastenerGroups[0].installations[0].tightenedAt, now)

        draft.removePhoto(photo)
        XCTAssertTrue(draft.photos.isEmpty)
        XCTAssertTrue(draft.fastenerGroups[0].installations[0].photoIDs.isEmpty)
        XCTAssertTrue(draft.fastenerGroups[0].removalPhotoIDs.isEmpty)
    }

    func testUnlinkAndRemoveFastener() throws {
        var draft = MaintenanceDraft(vehicleID: VehicleID(), kind: .heavy, now: now)
        draft.addFastenerGroup()
        let groupID = draft.fastenerGroups[0].id
        draft.addFastener(to: groupID)
        let evidenceID = draft.fastenerGroups[0].installations[0].id
        let photo = PhotoID()
        draft.addPhoto(MaintenancePhoto(id: photo, capturedAt: now))
        draft.linkPhoto(photo, groupID: groupID, evidenceID: evidenceID)
        draft.unlinkPhoto(photo, groupID: groupID, evidenceID: evidenceID)
        XCTAssertTrue(draft.fastenerGroups[0].installations[0].photoIDs.isEmpty)
        draft.removeFastener(groupID: groupID, evidenceID: evidenceID)
        XCTAssertTrue(draft.fastenerGroups[0].installations.isEmpty)
        draft.removeFastenerGroup(groupID)
        XCTAssertTrue(draft.fastenerGroups.isEmpty)
    }

    func testValidation() {
        var draft = MaintenanceDraft(vehicleID: VehicleID(), kind: .heavy, now: now)
        XCTAssertEqual(draft.issues(), [.titleRequired])
        draft.title = "  Overhaul "
        XCTAssertTrue(draft.issues().isEmpty)
        draft.workItems = []
        draft.odometerKilometers = -1
        XCTAssertEqual(Set(draft.issues()), [.workItemRequired, .odometerInvalid])
        draft.addWorkItem()
        draft.odometerKilometers = 0
        draft.addFastenerGroup()
        let groupID = draft.fastenerGroups[0].id
        XCTAssertEqual(draft.issues(), [.fastenerGroupNameRequired(groupID)])
        draft.fastenerGroups[0].name = "Head cover"
        draft.addFastener(to: groupID)
        draft.fastenerGroups[0].installations[0].torqueNewtonMeters = -3
        XCTAssertEqual(draft.issues(), [.fastenerValueInvalid(groupID)])
    }

    func testMakeRecordDropsFastenerGroupsForLightAndSetsModifiedAt() {
        var draft = MaintenanceDraft(vehicleID: VehicleID(), kind: .light, now: now)
        draft.title = " Oil "
        draft.fastenerGroups = [MaintenanceFastenerGroup(name: "x")]
        let stamp = now.addingTimeInterval(5)
        let record = draft.makeRecord(modifiedAt: stamp)
        XCTAssertEqual(record.title, "Oil")
        XCTAssertTrue(record.fastenerGroups.isEmpty)
        XCTAssertEqual(record.modifiedAt, stamp)
        XCTAssertEqual(record.createdAt, now)
    }
}
