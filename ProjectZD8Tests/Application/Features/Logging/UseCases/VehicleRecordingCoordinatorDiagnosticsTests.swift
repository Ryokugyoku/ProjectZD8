import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator` が、車両照合の失敗・別セッション進行中の開始辞退・想定外の状態での開始要求を
/// 診断ポートへ伝えることを検証します。
@MainActor
final class VehicleRecordingCoordinatorDiagnosticsTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 登録済み車両です。
    private let registered = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// テスト中に作った照合の gate です。終了時に未解決の待ちを解放します。
    private var gates: [AdapterLinkSupervisionScriptedResponses<Bool>] = []

    /// 責務: 未解決の照合の待ちを失敗として解放します。
    override func tearDown() async throws {
        gates.forEach { $0.failAllPending() }
        gates.removeAll()
        try await super.tearDown()
    }

    /// サインイン済みで車両を登録した組み立てを作ります。
    ///
    /// 責務: 照合とセッションが同じアカウントを使う状態を作ります。
    /// - Returns: 組み立て。
    private func signedInHarness() -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        return harness
    }

    /// 車両照合が失敗したら、そのエラーを診断ポートへ1回伝え、開始辞退は伝えません。
    ///
    /// 責務: 照合失敗の診断が注入したエラーで1件だけ記録されることを確認します。
    func testLookupFailureIsReportedToDiagnostics() async throws {
        let harness = signedInHarness()
        harness.vehicleRepository.loadFailure = VehicleRecordingTestError.vehicleLoadFailed

        try await harness.requestResidentStart(vin: registered.vin)

        XCTAssertEqual(harness.diagnostics.lookupFailures.count, 1)
        XCTAssertEqual(harness.diagnostics.lookupFailures.first as? VehicleRecordingTestError, .vehicleLoadFailed)
        XCTAssertEqual(harness.diagnostics.declineReasons, [])
    }

    /// 手動記録の実行中に開始要求が来たら、「別のセッションが進行中」として辞退を伝えます。
    ///
    /// 責務: 辞退の理由が診断ポートと `lastStartDeclineReason` に現れることを確認します。
    func testDeclineDuringManualRecordingIsReported() async throws {
        let harness = signedInHarness()
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: registered))

        try await harness.requestResidentStart(vin: registered.vin)

        XCTAssertEqual(harness.diagnostics.declineReasons, [.anotherSessionActive])
        XCTAssertEqual(harness.coordinator.lastStartDeclineReason, .anotherSessionActive)
    }

    /// 記録中に開始要求が重ねて来たら、想定外の状態(記録中)として辞退を伝え、記録は続きます。
    ///
    /// 責務: 理由に記録中の段階が入り、記録中のまま新しいテレメトリが始まらないことを確認します。
    func testDuplicateRequestWhileRecordingIsReportedAsBusy() async throws {
        let harness = signedInHarness()
        try await harness.requestResidentStart(vin: registered.vin)

        harness.coordinator.requestRecordingStart(H.residentRequest(vin: registered.vin))

        XCTAssertEqual(harness.diagnostics.declineReasons, [.coordinatorBusy(.recording)])
        XCTAssertEqual(harness.coordinator.phase, .recording)
        XCTAssertEqual(harness.telemetryRequests.count, 1)
    }

    /// 照合中に開始要求が重ねて来たら、想定外の状態(照合中)として辞退を伝えます。
    ///
    /// 責務: 理由に照合中の段階が入ることを確認します。
    func testDuplicateRequestWhileResolvingIsReportedAsBusy() async throws {
        let harness = signedInHarness()
        let gate = try await harness.requestResidentStartHoldingLookup(vin: registered.vin)
        gates.append(gate)

        harness.coordinator.requestRecordingStart(H.residentRequest(vin: registered.vin))

        XCTAssertEqual(harness.diagnostics.declineReasons, [.coordinatorBusy(.resolvingVehicle)])
        XCTAssertEqual(harness.coordinator.phase, .resolvingVehicle)
    }

    /// 正常に記録を始めた時は、診断ポートへ何も伝えず、前回の辞退理由も残しません。
    ///
    /// 責務: 辞退の後に正常な開始が続いた場合に、診断が増えず辞退理由が消えることを確認します。
    func testSuccessfulStartReportsNothing() async throws {
        let harness = signedInHarness()
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: registered))
        try await harness.requestResidentStart(vin: registered.vin)
        harness.telemetryDidEnd(reason: .userDisconnected)

        try await harness.requestResidentStart(vin: registered.vin)

        XCTAssertEqual(harness.coordinator.phase, .recording)
        XCTAssertEqual(harness.diagnostics.declineReasons, [.anotherSessionActive])
        XCTAssertTrue(harness.diagnostics.lookupFailures.isEmpty)
        XCTAssertNil(harness.coordinator.lastStartDeclineReason)
    }
}
