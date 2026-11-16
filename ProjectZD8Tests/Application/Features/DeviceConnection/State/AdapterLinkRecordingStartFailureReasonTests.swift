import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingStartFailureReason` の理由ごとの本文キーを検証します。
///
/// 仕様: U4 受け入れ条件 7(「記録を開始できませんでした」+ 理由: 車両を検知できなかった / サインインが必要 / アダプターが未設定)。
final class AdapterLinkRecordingStartFailureReasonTests: XCTestCase {
    /// 理由は3種類です。
    ///
    /// 責務: 仕様の3つの理由がそろい、ほかに無いことを確認します。
    func testThreeReasons() {
        XCTAssertEqual(
            Set(AdapterLinkRecordingStartFailureReason.allCases.map(\.bodyKey)).count,
            3
        )
        XCTAssertEqual(AdapterLinkRecordingStartFailureReason.allCases.count, 3)
    }

    /// 理由ごとに別の本文キーを返します。
    ///
    /// 責務: 各理由の本文キーが仕様の理由を表すキーであることを確認します。
    func testBodyKeyPerReason() {
        XCTAssertEqual(
            AdapterLinkRecordingStartFailureReason.vehicleNotDetected.bodyKey,
            "vehicle-detection-recording-start-failed-body-not-detected"
        )
        XCTAssertEqual(AdapterLinkRecordingStartFailureReason.signInRequired.bodyKey, "vehicle-detection-recording-start-failed-body-sign-in")
        XCTAssertEqual(
            AdapterLinkRecordingStartFailureReason.adapterNotConfigured.bodyKey,
            "vehicle-detection-recording-start-failed-body-no-adapter"
        )
    }
}
