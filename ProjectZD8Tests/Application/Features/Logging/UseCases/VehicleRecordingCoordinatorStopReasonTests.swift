import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleRecordingCoordinator` が、監視からの理由付きの停止要求を保存すべき終了理由でテレメトリへ渡し、
/// 記録中のリンク可用性の変化を常駐リンクで始めた記録の間だけテレメトリへ伝えることを検証します。
///
/// 仕様: U2 受け入れ条件 4・9〜13。
@MainActor
final class VehicleRecordingCoordinatorStopReasonTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 照合で一致させる登録済み車両です。
    private let registered = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// 常駐リンクから始めた記録が進行中の組み立てを作ります。
    ///
    /// 責務: サインインと車両登録の後、常駐リンクからの記録を記録中まで進めます。
    /// - Returns: 記録中の組み立て。
    private func recordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        try await harness.requestResidentStart(vin: registered.vin, file: file, line: line)
        XCTAssertEqual(harness.coordinator.phase, .recording, file: file, line: line)
        return harness
    }

    /// 停止要求の理由は、保存すべき終了理由(どれもユーザー切断ではない)へ写してテレメトリへ渡し、終了後は同じ理由で保存・通知されます。
    ///
    /// 責務: 4つの停止理由ごとに、テレメトリへ渡る理由・保存された理由・監視へ返る理由が一致することを確認します(仕様 9〜13)。
    func testStopReasonIsPassedToTelemetryAndPersisted() async throws {
        let expected: [(AdapterLinkRecordingStopReason, ConnectionSessionEndReason)] = [
            (.accountSignedOut, .accountSignedOut), (.superseded, .superseded),
            (.connectionTargetLost, .connectionLost), (.supervisionStopped, .connectionLost),
        ]
        for (reason, endReason) in expected {
            let harness = try await recordingHarness()

            harness.coordinator.requestRecordingStop(reason: reason)
            harness.telemetryDidEnd(reason: endReason)

            XCTAssertEqual(harness.stopTelemetryReasons, [endReason], "\(reason)")
            XCTAssertEqual(harness.sessionRepository.saved.last?.endReason, endReason, "\(reason)")
            XCTAssertEqual(harness.finishReasons, [endReason], "\(reason)")
        }
    }

    /// 常駐リンクで始めた記録の間は、リンク可用性の変化をそのままの順でテレメトリへ伝えます。
    ///
    /// 責務: 断・復帰の順に1件ずつ伝わり、停止は呼ばれないことを確認します(仕様 4)。
    func testLinkAvailabilityIsForwardedWhileResidentRecording() async throws {
        let harness = try await recordingHarness()

        harness.coordinator.recordingLinkAvailabilityDidChange(isAvailable: false)
        harness.coordinator.recordingLinkAvailabilityDidChange(isAvailable: true)

        XCTAssertEqual(harness.telemetryLinkAvailabilityChanges, [false, true])
        XCTAssertEqual(harness.stopTelemetryCount, 0)
    }

    /// 記録中でない時(待機中・記録の終了後)のリンク可用性の変化は、テレメトリへ伝えません。
    ///
    /// 責務: 記録前と記録終了後の変化で、伝えた変化が0件のままであることを確認します(仕様 4)。
    func testLinkAvailabilityIsIgnoredOutsideResidentRecording() async throws {
        let idle = VehicleRecordingCoordinatorHarness()
        idle.coordinator.recordingLinkAvailabilityDidChange(isAvailable: true)
        XCTAssertEqual(idle.telemetryLinkAvailabilityChanges, [])

        let finished = try await recordingHarness()
        finished.telemetryDidEnd(reason: .connectionLost)
        finished.coordinator.recordingLinkAvailabilityDidChange(isAvailable: false)
        XCTAssertEqual(finished.telemetryLinkAvailabilityChanges, [])
    }

    /// 手動接続で始めた記録の間は、常駐リンクのリンク可用性の変化をテレメトリへ伝えません。
    ///
    /// 責務: 手動記録中の変化で、伝えた変化が0件のままであることを確認します(U2「変えないもの」)。
    func testLinkAvailabilityIsIgnoredDuringManualRecording() async throws {
        let harness = VehicleRecordingCoordinatorHarness()
        harness.signIn()
        harness.register([registered])
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: registered))
        XCTAssertEqual(harness.manualUseBeganCount, 1, "手動記録の開始")

        harness.coordinator.recordingLinkAvailabilityDidChange(isAvailable: false)

        XCTAssertEqual(harness.telemetryLinkAvailabilityChanges, [])
    }
}
