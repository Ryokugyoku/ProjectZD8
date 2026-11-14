import XCTest
@testable import ProjectZD8

/// 取得ループの終了理由を接続セッションの終了原因へ変換することを検証します。
final class LiveTelemetryAcquisitionTerminationTests: XCTestCase {
    /// 4つの終了理由がそれぞれの終了原因へ変換されます。
    ///
    /// 責務: 停止=ユーザー切断、無応答=車両無応答、接続断=接続断、保存失敗=取得失敗の対応を確認します。
    func testSessionEndReasonForEachTermination() {
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.stopped.sessionEndReason, .userDisconnected)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.noVehicleResponse.sessionEndReason, .vehicleNoResponse)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.connectionLost.sessionEndReason, .connectionLost)
        XCTAssertEqual(LiveTelemetryAcquisitionTermination.recordingFailed.sessionEndReason, .acquisitionFailed)
    }
}
