import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator` が常駐リンクから始めた記録の停止と終了を扱い、
/// 状態機械へ記録終了をちょうど1回伝え、手動記録との競合を仕様どおりに解決することを検証します。
@MainActor
final class VehicleRecordingCoordinatorFinishTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 照合で一致させる登録済み車両です。
    private let registered = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// 手動接続で確定する別の登録済み車両です。
    private let manualVehicle = VehicleProfile(vin: "JF1ZD8A11P9000009", name: "Manual")

    /// テスト中に作った照合の gate です。途中で失敗しても待ちが残らないよう、終了時に解放します。
    private var gates: [AdapterLinkSupervisionScriptedResponses<Bool>] = []

    /// 責務: 未解決の照合の待ちを失敗として解放します。
    override func tearDown() async throws {
        gates.forEach { $0.failAllPending() }
        gates.removeAll()
        try await super.tearDown()
    }

    /// 常駐リンクから始めた記録が進行中の組み立てを作ります。
    ///
    /// 責務: サインインと車両登録の後、常駐リンクからの記録を記録中まで進めます。
    /// - Returns: 記録中の組み立て。
    private func recordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered, manualVehicle])
        try await harness.requestResidentStart(vin: registered.vin, file: file, line: line)
        XCTAssertEqual(harness.coordinator.phase, .recording, file: file, line: line)
        XCTAssertEqual(harness.finishCount, 0, file: file, line: line)
        return harness
    }

    /// 状態機械からの停止要求でテレメトリを止め、テレメトリ終了で接続セッションが終わり、記録終了を1回伝えます。
    ///
    /// 責務: 停止要求の時点ではまだ終了を伝えず、テレメトリ終了後に1回だけ伝えることを確認します。
    func testStopRequestStopsTelemetryAndFinishesOnceAfterTelemetryEnds() async throws {
        let harness = try await recordingHarness()

        harness.coordinator.requestRecordingStop()

        XCTAssertEqual(harness.stopTelemetryCount, 1)
        XCTAssertEqual(harness.finishCount, 0)
        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertNil(harness.lifecycle.activeSession)
        XCTAssertEqual(harness.sessionRepository.saved.last?.endReason, .userDisconnected)
        XCTAssertEqual(harness.coordinator.phase, .idle)
    }

    /// どの理由でテレメトリが終わっても、記録終了はちょうど1回伝わります。
    ///
    /// 責務: 手動停止・取得失敗・無応答・リンク断・サインアウトのそれぞれで、終了通知が1回で、重ねた終了通知で増えないことを確認します。
    func testFinishIsReportedExactlyOnceForEveryEndReason() async throws {
        let reasons: [ConnectionSessionEndReason] = [
            .userDisconnected, .acquisitionFailed, .vehicleNoResponse, .connectionLost, .accountSignedOut,
        ]
        for reason in reasons {
            let harness = try await recordingHarness()
            harness.telemetryDidEnd(reason: reason)
            harness.telemetryDidEnd(reason: reason)
            harness.coordinator.requestRecordingStop()
            XCTAssertEqual(harness.finishCount, 1, "\(reason)")
            XCTAssertEqual(harness.coordinator.phase, .idle, "\(reason)")
        }
    }

    /// 停止要求なしにテレメトリが終わった(猶予切れなど)時は、その終了理由がそのまま監視へ届き、保存される理由とも一致します。
    ///
    /// 責務: リンク断の猶予切れ(接続断)を含む各理由で、監視へ渡る理由・保存された理由が同じで、テレメトリの停止を呼ばないことを確認します(U2 受け入れ条件 3・13)。
    func testEndReasonWithoutStopRequestIsForwardedUnchanged() async throws {
        let reasons: [ConnectionSessionEndReason] = [.connectionLost, .vehicleNoResponse, .acquisitionFailed]
        for reason in reasons {
            let harness = try await recordingHarness()

            harness.telemetryDidEnd(reason: reason)

            XCTAssertEqual(harness.finishReasons, [reason], "\(reason)")
            XCTAssertEqual(harness.sessionRepository.saved.last?.endReason, reason, "\(reason)")
            XCTAssertEqual(harness.stopTelemetryCount, 0, "\(reason)")
        }
    }

    /// 停止要求の後にテレメトリが終わっても、終了は1回だけです。
    ///
    /// 責務: 停止要求と終了通知が両方来ても二重に伝えないことを確認します。
    func testStopRequestFollowedByTelemetryEndFinishesOnce() async throws {
        let harness = try await recordingHarness()

        harness.coordinator.requestRecordingStop()
        harness.telemetryDidEnd(reason: .userDisconnected)
        harness.coordinator.requestRecordingStop()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.stopTelemetryCount, 1)
    }

    /// 照合中の停止要求では照合結果を捨て、記録を始めずに終了を1回伝えます。
    ///
    /// 責務: 停止後に照合が終わってもセッション・テレメトリが始まらず、終了が増えないことを確認します。
    func testStopDuringLookupDiscardsLookupAndFinishesOnce() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        let gate = try await harness.requestResidentStartHoldingLookup(vin: registered.vin)
        gates.append(gate)

        harness.coordinator.requestRecordingStop()
        XCTAssertEqual(harness.finishCount, 1)
        gate.resumeOldest(with: .success(true))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertTrue(harness.telemetryRequests.isEmpty)
        XCTAssertNil(harness.lifecycle.activeSession)
        XCTAssertEqual(harness.coordinator.phase, .idle)
    }

    /// 開始に失敗して終了を伝えた後の終了通知・停止要求で、終了が重ねて伝わりません。
    ///
    /// 責務: 未サインインによる開始失敗の後も終了が1回のままであることを確認します。
    func testStartFailureFinishIsNotRepeatedByLaterEvents() async throws {
        let harness = VehicleRecordingCoordinatorHarness()

        try await harness.requestResidentStart(vin: registered.vin)
        harness.coordinator.telemetryDidEnd(reason: .userDisconnected)
        harness.coordinator.requestRecordingStop()

        XCTAssertEqual(harness.finishCount, 1)
    }

    /// 手動記録の実行中に常駐リンクから開始要求が来たら、新しい記録を始めず終了を伝えます。
    ///
    /// 責務: 手動のセッションとテレメトリがそのまま残り、終了が1回伝わることを確認します。
    func testResidentStartDuringManualRecordingIsDeclined() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: manualVehicle))
        let manualSession = try XCTUnwrap(harness.lifecycle.activeSession)

        try await harness.requestResidentStart(vin: registered.vin)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(harness.telemetryRequests.first?.vehicle?.id, manualVehicle.id)
        XCTAssertEqual(harness.lifecycle.activeSession?.id, manualSession.id)
        XCTAssertEqual(harness.coordinator.phase, .idle)
    }

    /// 手動記録の終了は状態機械への記録終了として伝えません。
    ///
    /// 責務: 手動で始めた記録のテレメトリ終了で、監視への終了通知が起きないことを確認します。
    func testManualRecordingEndIsNotReportedAsSupervisedFinish() {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: manualVehicle))

        harness.telemetryDidEnd(reason: .userDisconnected)

        XCTAssertEqual(harness.finishCount, 0)
    }

    /// 常駐リンクの記録中に手動で記録を始めたら、手動が優先され、状態機械へ終了を伝えます。
    ///
    /// 責務: 手動のテレメトリが始まり、終了が1回伝わり、その後の手動記録の終了で終了が増えないことを確認します。
    func testManualStartDuringResidentRecordingTakesOverAndFinishesOnce() async throws {
        let harness = try await recordingHarness()

        harness.coordinator.startManualRecording(H.manualRequest(vehicle: manualVehicle))

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.telemetryRequests.count, 2)
        XCTAssertEqual(harness.telemetryRequests.last?.vehicle?.id, manualVehicle.id)
        XCTAssertEqual(harness.lifecycle.activeSession?.vehicle?.id, manualVehicle.id)
        XCTAssertEqual(harness.coordinator.phase, .idle)
        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.finishCount, 1)
    }

    /// 照合中に手動で記録を始めたら、照合結果を捨てて手動を優先し、終了を1回伝えます。
    ///
    /// 責務: 照合が後から終わっても常駐リンク側のテレメトリが始まらないことを確認します。
    func testManualStartDuringLookupDiscardsLookup() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        let gate = try await harness.requestResidentStartHoldingLookup(vin: registered.vin)
        gates.append(gate)

        harness.coordinator.startManualRecording(H.manualRequest(vehicle: manualVehicle))
        gate.resumeOldest(with: .success(true))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.telemetryRequests.count, 1)
        XCTAssertEqual(harness.telemetryRequests.first?.vehicle?.id, manualVehicle.id)
        XCTAssertEqual(harness.lifecycle.activeSession?.vehicle?.id, manualVehicle.id)
    }
}
