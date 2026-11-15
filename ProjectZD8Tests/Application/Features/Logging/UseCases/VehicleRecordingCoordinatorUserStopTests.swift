import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator` が、常駐リンクの記録のユーザー切断を理由付きで監視へ伝え、
/// 切断の後も手動記録を始められることを検証します。
@MainActor
final class VehicleRecordingCoordinatorUserStopTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 照合で一致させる登録済み車両です。
    private let registered = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// 常駐リンクの記録が進行中の組み立てを作ります。
    ///
    /// 責務: サインインと車両登録の後、常駐リンクからの記録を記録中まで進めます。
    private func recordingHarness() async throws -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        try await harness.requestResidentStart(vin: registered.vin)
        XCTAssertEqual(harness.coordinator.phase, .recording)
        return harness
    }

    /// 常駐リンクの記録がユーザー切断で終わると、監視へ `.userDisconnected` が1回だけ渡ります。
    ///
    /// 責務: 終了理由が監視への通知にそのまま渡ることを確認します。
    func testUserDisconnectIsReportedToSupervisionWithReason() async throws {
        let harness = try await recordingHarness()
        harness.telemetryDidEnd(reason: .userDisconnected)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.finishReasons, [.userDisconnected])
    }

    /// 監視へ終了を伝えた後(抑止中に当たる)でも、手動記録のテレメトリを始められます。
    ///
    /// 責務: 手動記録の開始でテレメトリ開始が1回呼ばれ、手動使用の開始が1回伝わることを確認します。
    func testManualRecordingStartsAfterUserDisconnect() async throws {
        let harness = try await recordingHarness()
        harness.telemetryDidEnd(reason: .userDisconnected)
        let requests = harness.telemetryRequests.count

        harness.coordinator.startManualRecording(H.manualRequest(vehicle: registered))

        XCTAssertEqual(harness.telemetryRequests.count, requests + 1)
        XCTAssertEqual(harness.manualUseBeganCount, 1)
    }
}
