import Foundation
import XCTest
@testable import ProjectZD8

/// 手動接続で識別した車両が未登録だった時(`VehicleRecordingStartRequest.manualUnregisteredConnection`)、
/// 調停役がそれを手動の記録中として扱い、常駐リンクの記録開始を受け付けず、記録の終わりまで手動使用を続けることを検証します。
@MainActor
final class VehicleRecordingCoordinatorManualUnregisteredTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias H = VehicleRecordingCoordinatorHarness
    /// 識別で読めた未登録車両のVIN(ZD8 形式)です。
    private static let vin = "JF1ZD8A11P9000001"

    /// サインイン済みの組み立てを作ります。
    ///
    /// 責務: 登録済み車両なしでサインインした組み立てを返します。
    /// - Returns: 組み立て。
    private func signedInHarness() -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        return harness
    }

    /// 識別観測から未登録の記録開始要求を作ります。
    ///
    /// 責務: 指定VINを読めた識別観測で `manualUnregisteredConnection` を呼びます。
    /// - Parameter vin: 識別で読めたVIN。
    /// - Returns: 記録開始要求。
    private func unregisteredRequest(vin: String? = vin) -> VehicleRecordingStartRequest {
        .manualUnregisteredConnection(
            endpoint: H.endpoint,
            identification: VehicleIdentificationSnapshot(vin: vin, fields: [], observedAt: Date(timeIntervalSince1970: 0))
        )
    }

    /// 未登録の手動記録は、手動使用を始めてから車両なしのセッションを開始し、観測VINを保存してからテレメトリを始めます。
    ///
    /// 責務: 手動使用が記録中になり、テレメトリ要求が車両なし・観測VINあり・型式コードなしで1件出ることを確認します。
    func testUnregisteredManualRecordingStartsWithObservedVIN() {
        let harness = signedInHarness()

        harness.coordinator.startManualRecording(unregisteredRequest())

        XCTAssertEqual(harness.coordinator.manualAdapterUse, .recording)
        XCTAssertEqual(harness.events, ["manual.began", "session.start", "session.vin", "telemetry.start"])
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertNil(harness.telemetryRequests.first?.vehicle)
        XCTAssertEqual(harness.telemetryRequests.first?.observedVIN, Self.vin)
        XCTAssertNil(harness.telemetryRequests.first?.vehicleModelCode)
        XCTAssertNil(harness.lifecycle.activeSession?.vehicle)
        XCTAssertEqual(harness.lifecycle.activeSession?.observedVIN, Self.vin)
    }

    /// VINを読めなかった未登録の手動記録でも記録中になり、観測VINは保存しません。
    ///
    /// 責務: 観測VINなしでもセッション開始とテレメトリ開始が行われることを確認します。
    func testUnregisteredManualRecordingWithoutVINStillRecords() {
        let harness = signedInHarness()

        harness.coordinator.startManualRecording(unregisteredRequest(vin: nil))

        XCTAssertEqual(harness.coordinator.manualAdapterUse, .recording)
        XCTAssertEqual(harness.events, ["manual.began", "session.start", "telemetry.start"])
        XCTAssertNil(harness.lifecycle.activeSession?.observedVIN)
    }

    /// 識別から未登録の記録へ続いた場合、識別が終わっても手動使用は終わらず、記録の終了で1回だけ終わります。
    ///
    /// 責務: 登録確認の表示中も常駐リンク監視の抑止が続く(「使い終えた」が出ない)ことを確認します。
    func testIdentificationEndDuringUnregisteredRecordingKeepsManualUse() {
        let harness = signedInHarness()
        harness.coordinator.manualConnectionIdentificationWillBegin()
        harness.coordinator.startManualRecording(unregisteredRequest())

        harness.coordinator.manualConnectionIdentificationDidEnd()
        XCTAssertEqual(harness.coordinator.manualAdapterUse, .recording)
        XCTAssertEqual(harness.manualUseEndedCount, 0)

        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.coordinator.manualAdapterUse, .idle)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }

    /// 未登録の手動記録の間に常駐リンクから記録開始が来ても、別のセッションが進行中として断り、テレメトリは増えません。
    ///
    /// 責務: 手動の未登録記録が常駐リンクの記録と並行しないことを確認します。
    func testResidentStartDuringUnregisteredManualRecordingIsDeclined() async throws {
        let harness = signedInHarness()
        harness.coordinator.startManualRecording(unregisteredRequest())

        try await harness.requestResidentStart(vin: Self.vin)

        XCTAssertEqual(harness.coordinator.lastStartDeclineReason, .anotherSessionActive)
        XCTAssertEqual(harness.coordinator.phase, .idle)
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(harness.coordinator.manualAdapterUse, .recording)
    }

    /// 未登録の手動記録の途中で車両を登録しても、新しい記録は始まらず、同じセッションに車両が入ります。
    ///
    /// 責務: 登録後は現在セッションへ関連付けるだけで、テレメトリ要求と手動使用の回数が変わらないことを確認します。
    func testRegistrationDuringUnregisteredRecordingBindsWithoutNewRecording() throws {
        let harness = signedInHarness()
        harness.coordinator.startManualRecording(unregisteredRequest())
        let session = try XCTUnwrap(harness.lifecycle.activeSession)
        let vehicle = VehicleProfile(vin: Self.vin, name: "BRZ")

        harness.lifecycle.send(.unregisteredVehicleRegistered(vehicle))

        XCTAssertEqual(harness.lifecycle.activeSession?.id, session.id)
        XCTAssertEqual(harness.lifecycle.activeSession?.vehicle, ConnectionSessionVehicle(profile: vehicle))
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
    }
}
