import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループの終了理由を接続セッションの終了原因・終了時刻へ変換することを検証します。
final class LiveTelemetryAcquisitionTerminationTests: XCTestCase {
    /// 停止=ユーザー切断、猶予切れ=原因に応じた終了原因、保存失敗=取得失敗です。
    ///
    /// 責務: 終了原因の対応を確認します。
    func testSessionEndReasonForEachTermination() {
        let at = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.stopped.sessionEndReason, .userDisconnected)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.gracePeriodExpired(cause: .responseStall, lastReceivedAt: at).sessionEndReason, .vehicleNoResponse)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.gracePeriodExpired(cause: .linkLost, lastReceivedAt: at).sessionEndReason, .connectionLost)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.recordingFailed.sessionEndReason, .acquisitionFailed)
    }

    /// 終了時刻を指定するのは猶予切れだけで、その値は最後に正常応答を受けた実時刻です。
    ///
    /// 責務: 3つの終了理由の終了時刻を確認します。
    func testSessionEndedAtOnlyForGraceExpiry() {
        let at = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.gracePeriodExpired(cause: .linkLost, lastReceivedAt: at).sessionEndedAt, at)
        XCTAssertNil(LiveTelemetryAcquisitionTermination.stopped.sessionEndedAt)
        XCTAssertNil(LiveTelemetryAcquisitionTermination.recordingFailed.sessionEndedAt)
    }
}
