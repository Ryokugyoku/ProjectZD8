import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` の表示用車両写真の扱いのテストです。
@MainActor
final class RecordingSessionActivityUseCasePhotoTests: XCTestCase {
    /// 責務: 写真のある登録車両では、保存したファイル名を表示へ載せることを確認します。
    func testStoredPhotoFileNameAppearsInContent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        let vehicle = harness.registerVehicle()
        await harness.send(harness.state(.loaded, speed: 10, vehicle: vehicle))
        XCTAssertEqual(harness.photos.storedVehicleIDs, [vehicle])
        XCTAssertEqual(harness.activity.startedContents.first?.vehiclePhotoFileName, "vehicle-photo.jpg")
    }

    /// 責務: 写真の保存に失敗しても写真なしで表示を続け、診断へ残すことを確認します。
    func testPhotoStoreFailureContinuesWithoutPhotoAndIsRecorded() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.photos.replaceError = RecordingSessionActivityTestError(label: "store")
        let vehicle = harness.registerVehicle()
        await harness.send(harness.state(.loaded, speed: 10, vehicle: vehicle))
        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertNil(harness.activity.startedContents[0].vehiclePhotoFileName)
        XCTAssertEqual(harness.diagnostics.failedOperations, [.storePhoto])
    }

    /// 責務: セッション終了時に古い写真の削除を呼ぶことを確認します。
    func testSessionEndRemovesPhotos() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        let vehicle = harness.registerVehicle()
        await harness.send(harness.state(.loaded, speed: 10, vehicle: vehicle))
        XCTAssertEqual(harness.photos.removeAllCount, 0)
        await harness.send(harness.state(.idle, vehicle: vehicle))
        XCTAssertEqual(harness.photos.removeAllCount, 1)
    }

    /// 責務: 写真の無い車両へ変わると、古い写真の削除を呼び、写真なしで更新することを確認します。
    func testVehicleChangeToPhotolessVehicleRemovesOldPhoto() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        let first = harness.registerVehicle()
        let second = harness.registerVehicle(name: "WRX", photo: nil)
        await harness.send(harness.state(.loaded, speed: 10, vehicle: first))
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 10, vehicle: second))
        XCTAssertEqual(harness.photos.removeAllCount, 1)
        XCTAssertEqual(harness.activity.updatedContents.last?.vehicle,
                       RecordingSessionActivityVehicleLabel(vehicleName: "WRX"))
        XCTAssertNil(harness.activity.updatedContents.last?.vehiclePhotoFileName)
    }

    /// 責務: 別の写真付き車両へ変わると、新しい車両の写真を保存し直すことを確認します。
    func testVehicleChangeToAnotherPhotoVehicleReplacesPhoto() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        let first = harness.registerVehicle()
        let second = harness.registerVehicle(name: "WRX")
        await harness.send(harness.state(.loaded, speed: 10, vehicle: first))
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 10, vehicle: second))
        XCTAssertEqual(harness.photos.storedVehicleIDs, [first, second])
    }
}
