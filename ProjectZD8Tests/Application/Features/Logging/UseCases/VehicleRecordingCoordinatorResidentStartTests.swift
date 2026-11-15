import Foundation
import XCTest
@testable import ProjectZD8

/// 常駐リンク監視からの記録開始要求を受けた `VehicleRecordingCoordinator` が、
/// VIN で登録済み車両を照合し、接続セッションとテレメトリを仕様どおりに始めることを検証します。
@MainActor
final class VehicleRecordingCoordinatorResidentStartTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// ZD8 型式に該当する登録済み車両のVINです。
    private static let zd8VIN = "JF1ZD8A11P9000001"

    /// ZD8 型式に該当しないVINです。
    private static let otherVIN = "WVWZZZ1KZ6W000002"

    /// 登録済み車両を作ります。
    ///
    /// 責務: 指定VINと名前の車両を返します。
    /// - Parameters:
    ///   - vin: 車両のVIN。
    ///   - name: 車両名。
    /// - Returns: 登録済み車両。
    private func vehicle(vin: String, name: String = "BRZ") -> VehicleProfile {
        VehicleProfile(vin: vin, name: name)
    }

    /// サインイン済みで指定車両を登録した組み立てを作ります。
    ///
    /// 責務: 照合とセッションが同じアカウントを使う状態を作ります。
    /// - Parameter vehicles: 登録済み車両。
    /// - Returns: 組み立て。
    private func signedInHarness(registering vehicles: [VehicleProfile]) -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register(vehicles)
        return harness
    }

    /// VIN が登録済み車両と(大文字小文字を区別せず)一致すれば、その車両で記録を始めます。
    ///
    /// 責務: セッションに車両が確定し、テレメトリ要求に終端・車両・型式コード・判定結果・観測VINが入ることを確認します。
    func testMatchingVINStartsRecordingWithRegisteredVehicle() async throws {
        let registered = vehicle(vin: Self.zd8VIN)
        let harness = signedInHarness(registering: [vehicle(vin: Self.otherVIN, name: "Other"), registered])

        try await harness.requestResidentStart(vin: Self.zd8VIN.lowercased())

        XCTAssertEqual(harness.coordinator.phase, .recording)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.lifecycle.activeSession?.vehicle, ConnectionSessionVehicle(profile: registered))
        let request = try XCTUnwrap(harness.telemetryRequests.first)
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(request.endpoint, H.endpoint)
        XCTAssertEqual(request.vehicle?.id, registered.id)
        XCTAssertEqual(request.vehicleModelCode, ZD8VehicleModelPolicy.modelCode)
        XCTAssertEqual(request.adapterProbeEvidence, H.evidence)
        XCTAssertEqual(request.observedVIN, Self.zd8VIN.lowercased())
    }

    /// 一致した場合の手順は「セッション開始 → 車両確定 → テレメトリ開始」の順です。
    ///
    /// 責務: 保存と出力の発生順を確認します(車両確定済みのセッションには観測VINの保存は起きない)。
    func testMatchingVINRunsStepsInOrder() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])

        try await harness.requestResidentStart(vin: Self.zd8VIN)

        XCTAssertEqual(harness.events, ["session.start", "session.vehicle", "telemetry.start"])
    }

    /// 一致しない VIN では車両なしで記録を始め、VIN を観測値として残します。
    ///
    /// 責務: セッションは開始され車両は未確定、観測VINが保存され、テレメトリ要求の車両と型式コードが nil であることを確認します。
    func testUnmatchedVINStartsRecordingWithoutVehicleAndKeepsObservedVIN() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])

        try await harness.requestResidentStart(vin: Self.otherVIN)

        XCTAssertEqual(harness.coordinator.phase, .recording)
        let session = try XCTUnwrap(harness.lifecycle.activeSession)
        XCTAssertNil(session.vehicle)
        XCTAssertEqual(session.observedVIN, Self.otherVIN)
        let request = try XCTUnwrap(harness.telemetryRequests.first)
        XCTAssertNil(request.vehicle)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertEqual(request.observedVIN, Self.otherVIN)
        XCTAssertEqual(request.endpoint, H.endpoint)
        XCTAssertEqual(request.adapterProbeEvidence, H.evidence)
        XCTAssertEqual(harness.events, ["session.start", "session.vin", "telemetry.start"])
    }

    /// ZD8 の形をした VIN でも、登録済み車両と一致しなければテレメトリ要求の型式コードは nil です。
    ///
    /// 責務: 仕様「一致しない場合は車両 ID と型式コードは nil」を、型式に該当する VIN で確認します。
    func testUnmatchedZD8ShapedVINHasNoModelCode() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.otherVIN)])

        try await harness.requestResidentStart(vin: Self.zd8VIN)

        let request = try XCTUnwrap(harness.telemetryRequests.first)
        XCTAssertNil(request.vehicle)
        XCTAssertNil(request.vehicleModelCode, "未登録車両の記録に型式コードが付いた")
    }

    /// VIN が nil なら車両なしで始め、観測VINは記録しません。
    ///
    /// 責務: セッションは開始のみ保存され、車両・観測VIN・型式コードがすべて nil であることを確認します。
    func testNilVINStartsRecordingWithoutVehicleOrObservedVIN() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])

        try await harness.requestResidentStart(vin: nil)

        XCTAssertEqual(harness.coordinator.phase, .recording)
        let session = try XCTUnwrap(harness.lifecycle.activeSession)
        XCTAssertNil(session.vehicle)
        XCTAssertNil(session.observedVIN)
        let request = try XCTUnwrap(harness.telemetryRequests.first)
        XCTAssertNil(request.vehicle)
        XCTAssertNil(request.observedVIN)
        XCTAssertNil(request.vehicleModelCode)
        XCTAssertEqual(harness.events, ["session.start", "telemetry.start"])
    }

    /// 車両照合が失敗しても車両なしで記録を続け、エラーを参照できる形で残します。
    ///
    /// 責務: 照合の throw で記録中になり、観測VINが残り、`lastVehicleLookupError` に注入したエラーが入ることを確認します。
    func testLookupFailureContinuesWithoutVehicleAndKeepsError() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])
        harness.vehicleRepository.loadFailure = VehicleRecordingTestError.vehicleLoadFailed

        try await harness.requestResidentStart(vin: Self.zd8VIN)

        XCTAssertEqual(harness.coordinator.phase, .recording)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.coordinator.lastVehicleLookupError as? VehicleRecordingTestError, .vehicleLoadFailed)
        let session = try XCTUnwrap(harness.lifecycle.activeSession)
        XCTAssertNil(session.vehicle)
        XCTAssertEqual(session.observedVIN, Self.zd8VIN)
        XCTAssertNil(try XCTUnwrap(harness.telemetryRequests.first).vehicle)
        XCTAssertEqual(harness.vehicleRepository.loadedAccounts, [H.account])
    }

    /// 照合に成功した時は照合エラーを残しません。
    ///
    /// 責務: 成功時の `lastVehicleLookupError` が nil であることを確認します。
    func testSuccessfulLookupLeavesNoError() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])

        try await harness.requestResidentStart(vin: Self.zd8VIN)

        XCTAssertNil(harness.coordinator.lastVehicleLookupError)
    }

    /// 未サインインでは記録を始めず、状態機械へ記録終了を1回伝えます。
    ///
    /// 責務: セッションの保存もテレメトリ開始も起きず、終了通知が1回で、待機へ戻ることを確認します。
    func testSignedOutDoesNotStartAndReportsFinishOnce() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.vehicleRepository.vehiclesByAccount[H.account] = [vehicle(vin: Self.zd8VIN)]

        try await harness.requestResidentStart(vin: Self.zd8VIN)

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertTrue(harness.telemetryRequests.isEmpty)
        XCTAssertTrue(harness.sessionRepository.saved.isEmpty)
        XCTAssertNil(harness.lifecycle.activeSession)
        XCTAssertEqual(harness.coordinator.phase, .idle)
    }

    /// セッションの保存に失敗したら成功扱いにせず、テレメトリを始めず、記録終了を1回伝えます。
    ///
    /// 責務: 開始失敗で記録中にならないことと終了通知の回数を確認します。
    func testSessionStartFailureReportsFinishOnceWithoutTelemetry() async throws {
        let harness = signedInHarness(registering: [vehicle(vin: Self.zd8VIN)])
        harness.sessionRepository.failsSave = true

        try await harness.requestResidentStart(vin: Self.zd8VIN)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertTrue(harness.telemetryRequests.isEmpty)
        XCTAssertEqual(harness.coordinator.phase, .idle)
        XCTAssertNil(harness.lifecycle.activeSession)
    }

    /// テレメトリの開始手段が無ければ開始失敗とし、セッションも始めず、記録終了を1回伝えます。
    ///
    /// 責務: 出力未設定時に記録中にならず、進行中のセッションが残らないことを確認します。
    func testMissingTelemetryStarterReportsFinishOnce() async throws {
        let harness = VehicleRecordingCoordinatorHarness(connectsTelemetry: false)
        harness.signIn()

        try await harness.requestResidentStart(vin: Self.zd8VIN)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.coordinator.phase, .idle)
        XCTAssertNil(harness.lifecycle.activeSession)
    }
}
