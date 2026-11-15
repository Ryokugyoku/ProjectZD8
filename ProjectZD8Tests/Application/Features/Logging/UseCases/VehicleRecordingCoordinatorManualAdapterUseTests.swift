import Foundation
import XCTest
@testable import ProjectZD8

/// 手動接続がアダプターを使い始めた/使い終えたことを、`VehicleRecordingCoordinator` が
/// 常駐リンク監視へ1回ずつ伝えることを検証します。
@MainActor
final class VehicleRecordingCoordinatorManualAdapterUseTests: XCTestCase {
    /// 組み立ての型です。
    private typealias H = VehicleRecordingCoordinatorHarness

    /// 手動接続で確定する登録済み車両です。
    private let vehicle = VehicleProfile(vin: "JF1ZD8A11P9000001", name: "BRZ")

    /// サインイン済みの組み立てを作ります。
    ///
    /// 責務: 手動記録のセッションを開始できる状態を作ります。
    /// - Parameter connectsTelemetry: テレメトリ開始の出力を設定するかどうか。
    /// - Returns: 組み立て。
    private func signedInHarness(connectsTelemetry: Bool = true) -> VehicleRecordingCoordinatorHarness {
        let harness = VehicleRecordingCoordinatorHarness(connectsTelemetry: connectsTelemetry)
        harness.signIn()
        return harness
    }

    /// 識別の開始で「使い始めた」が1回伝わり、まだ「使い終えた」は伝わりません。
    ///
    /// 責務: 識別開始の直後の通知回数を確認します。
    func testIdentificationBeginReportsBeganOnce() {
        let harness = signedInHarness()

        harness.coordinator.manualConnectionIdentificationWillBegin()

        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
    }

    /// 識別の失敗・キャンセル・登録画面への移行(識別が記録へ進まずに終わる)で「使い終えた」が1回伝わります。
    ///
    /// 責務: 識別の開始と終了だけで、開始1回・終了1回になり、記録が始まらないことを確認します。
    func testIdentificationEndingWithoutRecordingReportsEndedOnce() {
        let harness = signedInHarness()

        harness.coordinator.manualConnectionIdentificationWillBegin()
        harness.coordinator.manualConnectionIdentificationDidEnd()
        harness.coordinator.manualConnectionIdentificationDidEnd()

        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
        XCTAssertTrue(harness.telemetryRequests.isEmpty)
        XCTAssertEqual(harness.events, ["manual.began", "manual.ended"])
    }

    /// 識別から記録へ続く1回の手動使用では、「使い始めた」は1回で、記録の終了で「使い終えた」が1回伝わります。
    ///
    /// 責務: 識別開始 → 記録開始 → 識別終了 → テレメトリ終了の順で、途中に終了が出ないことを確認します。
    func testIdentificationFollowedByRecordingReportsOneUse() {
        let harness = signedInHarness()

        harness.coordinator.manualConnectionIdentificationWillBegin()
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: vehicle))
        harness.coordinator.manualConnectionIdentificationDidEnd()
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 0)

        harness.telemetryDidEnd(reason: .userDisconnected)

        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }

    /// 手動記録がどの理由で終わっても「使い終えた」が1回伝わり、重ねた終了通知で増えません。
    ///
    /// 責務: 停止・取得失敗・無応答・リンク断・サインアウトのそれぞれで終了が1回であることを確認します。
    func testManualRecordingEndReportsEndedOnceForEveryReason() {
        let reasons: [ConnectionSessionEndReason] = [
            .userDisconnected, .acquisitionFailed, .vehicleNoResponse, .connectionLost, .accountSignedOut,
        ]
        for reason in reasons {
            let harness = signedInHarness()
            harness.coordinator.manualConnectionIdentificationWillBegin()
            harness.coordinator.startManualRecording(H.manualRequest(vehicle: vehicle))
            harness.coordinator.manualConnectionIdentificationDidEnd()

            harness.telemetryDidEnd(reason: reason)
            harness.telemetryDidEnd(reason: reason)

            XCTAssertEqual(harness.manualUseBeganCount, 1, "\(reason)")
            XCTAssertEqual(harness.manualUseEndedCount, 1, "\(reason)")
        }
    }

    /// 登録画面での保存から記録を始めた時(識別とは別の手動使用)も、開始と終了が1回ずつ伝わります。
    ///
    /// 責務: 識別を経ない手動記録の開始で「使い始めた」が出て、終了で「使い終えた」が出ることを確認します。
    func testRecordingStartedWithoutIdentificationReportsOneUse() {
        let harness = signedInHarness()

        harness.coordinator.startManualRecording(H.manualRequest(vehicle: vehicle))
        XCTAssertEqual(harness.manualUseBeganCount, 1)
        harness.telemetryDidEnd(reason: .userDisconnected)

        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }

    /// 「使い始めた」は手動のテレメトリ開始より前に伝わります。
    ///
    /// 責務: 監視の抑止が手動の取得より先に効く順序であることを確認します。
    func testBeganIsReportedBeforeManualTelemetryStarts() {
        let harness = signedInHarness()

        harness.coordinator.startManualRecording(H.manualRequest(vehicle: vehicle))

        let began = harness.events.firstIndex(of: "manual.began")
        let telemetry = harness.events.firstIndex(of: "telemetry.start")
        XCTAssertNotNil(began)
        XCTAssertNotNil(telemetry)
        XCTAssertLessThan(began ?? .max, telemetry ?? .min)
    }

    /// 手動記録のテレメトリを始められなければ、「使い終えた」が1回伝わります。
    ///
    /// 責務: 開始手段が無い時に開始1回・終了1回で、後の終了通知で増えないことを確認します。
    func testTelemetryStartFailureReportsEndedOnce() {
        let harness = signedInHarness(connectsTelemetry: false)

        harness.coordinator.manualConnectionIdentificationWillBegin()
        harness.coordinator.startManualRecording(H.manualRequest(vehicle: vehicle))
        harness.coordinator.manualConnectionIdentificationDidEnd()
        harness.telemetryDidEnd(reason: .acquisitionFailed)

        XCTAssertEqual(harness.manualUseBeganCount, 1)
        XCTAssertEqual(harness.manualUseEndedCount, 1)
    }

    /// 「使い始めた」無しに「使い終えた」は伝わりません。
    ///
    /// 責務: 識別終了・テレメトリ終了だけを受けても通知が出ないことを確認します。
    func testEndedIsNeverReportedWithoutBegan() {
        let harness = signedInHarness()

        harness.coordinator.manualConnectionIdentificationDidEnd()
        harness.telemetryDidEnd(reason: .userDisconnected)

        XCTAssertEqual(harness.manualUseBeganCount, 0)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
    }

    /// 識別の開始が重なっても「使い始めた」は1回です。
    ///
    /// 責務: 識別中の再度の識別開始で通知が重ならないことを確認します。
    func testRepeatedIdentificationBeginReportsBeganOnce() {
        let harness = signedInHarness()

        harness.coordinator.manualConnectionIdentificationWillBegin()
        harness.coordinator.manualConnectionIdentificationWillBegin()

        XCTAssertEqual(harness.manualUseBeganCount, 1)
    }

    /// 常駐リンクから始めた記録は手動使用として伝えません。
    ///
    /// 責務: 常駐リンクの記録の開始と終了で手動使用の通知が出ないことを確認します。
    func testResidentRecordingIsNotReportedAsManualUse() async throws {
        let harness = signedInHarness()
        harness.register([vehicle])

        try await harness.requestResidentStart(vin: vehicle.vin)
        harness.telemetryDidEnd(reason: .userDisconnected)

        XCTAssertEqual(harness.manualUseBeganCount, 0)
        XCTAssertEqual(harness.manualUseEndedCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
    }
}
