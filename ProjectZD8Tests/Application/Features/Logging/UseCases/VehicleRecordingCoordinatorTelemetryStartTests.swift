import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator.telemetryDidStart()` が、常駐リンク監視から依頼された記録の取得が始まった時だけ、
/// 開始の確定を監視へ伝えることを検証します。
///
/// 仕様: U4 受け入れ条件 1〜3(確定の経路は記録側 → 調停役 → 監視。辞退・失敗・終わった記録・別の記録の確定は伝えない)。
@MainActor
final class VehicleRecordingCoordinatorTelemetryStartTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 登録済み車両です。
    private let registered = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// 照合を止めた台本です。終了時に保留を終わらせます。
    private var gates: [AdapterLinkSupervisionScriptedResponses<Bool>] = []

    /// 責務: 保留中の照合を終わらせます。
    override func tearDown() async throws {
        gates.forEach { $0.failAllPending() }
        gates.removeAll()
        try await super.tearDown()
    }

    /// サインイン済みで車両を登録し、常駐リンクの記録を始めた組み立てを返します。
    ///
    /// 責務: 調停役が記録中になった状態を作ります。
    /// - Returns: 組み立て。
    private func recordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        try await harness.requestResidentStart(vin: registered.vin, file: file, line: line)
        XCTAssertEqual(harness.coordinator.phase, .recording, file: file, line: line)
        return harness
    }

    /// 常駐リンクの記録中に取得が始まったら、開始の確定を監視へ1回伝えます。
    ///
    /// 責務: テレメトリ開始の後の `telemetryDidStart()` で確定が1回、テレメトリ開始より後に伝わることを確認します(受け入れ条件 1・3)。
    func testTelemetryStartDuringResidentRecordingConfirmsStart() async throws {
        let harness = try await recordingHarness()

        harness.coordinator.telemetryDidStart()

        XCTAssertEqual(harness.startConfirmationCount, 1)
        XCTAssertEqual(Array(harness.events.suffix(2)), ["telemetry.start", "supervision.start"])
        XCTAssertEqual(harness.coordinator.phase, .recording)
    }

    /// 開始要求を受けていない待機中の取得開始は、監視へ伝えません。
    ///
    /// 責務: 何も依頼されていない調停役で確定が0回であることを確認します(受け入れ条件 3)。
    func testTelemetryStartWhileIdleIsIgnored() {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.coordinator.telemetryDidStart()
        XCTAssertEqual(harness.startConfirmationCount, 0)
    }

    /// 辞退(未サインイン)した開始要求の後の取得開始は、監視へ伝えません。
    ///
    /// 責務: 記録が始まらずに終わった後の `telemetryDidStart()` で確定が0回であることを確認します(受け入れ条件 2)。
    func testTelemetryStartAfterDeclinedStartIsIgnored() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        try await harness.requestResidentStart(vin: registered.vin)
        XCTAssertEqual(harness.finishCount, 1)

        harness.coordinator.telemetryDidStart()

        XCTAssertEqual(harness.startConfirmationCount, 0)
    }

    /// 車両照合の最中(接続セッション作成前)の取得開始は、監視へ伝えません。
    ///
    /// 責務: 照合中の `telemetryDidStart()` で確定が0回であることを確認します(受け入れ条件 1)。
    func testTelemetryStartWhileResolvingVehicleIsIgnored() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        let gate = try await harness.requestResidentStartHoldingLookup(vin: registered.vin)
        gates.append(gate)

        harness.coordinator.telemetryDidStart()

        XCTAssertEqual(harness.startConfirmationCount, 0)
    }

    /// 記録が終わった後に届いた古い取得開始は、監視へ伝えません。
    ///
    /// 責務: テレメトリ終了の後の `telemetryDidStart()` で確定が0回であることを確認します(受け入れ条件 3)。
    func testTelemetryStartAfterRecordingEndedIsIgnored() async throws {
        let harness = try await recordingHarness()
        harness.telemetryDidEnd(reason: .connectionLost)

        harness.coordinator.telemetryDidStart()

        XCTAssertEqual(harness.startConfirmationCount, 0)
    }

    /// 手動接続で始めた記録の取得開始は、監視へ伝えません(別の記録)。
    ///
    /// 責務: 手動記録の `telemetryDidStart()`、常駐リンクの記録を手動が置き換えた後の `telemetryDidStart()` で確定が0回であることを確認します(受け入れ条件 3)。
    func testTelemetryStartOfManualRecordingIsIgnored() async throws {
        let manual = VehicleRecordingCoordinatorHarness()
        manual.signIn()
        manual.coordinator.startManualRecording(H.manualRequest(vehicle: registered))
        manual.coordinator.telemetryDidStart()
        XCTAssertEqual(manual.startConfirmationCount, 0)

        let replaced = try await recordingHarness()
        replaced.coordinator.startManualRecording(H.manualRequest(vehicle: registered))
        replaced.coordinator.telemetryDidStart()
        XCTAssertEqual(replaced.startConfirmationCount, 0)
    }
}
