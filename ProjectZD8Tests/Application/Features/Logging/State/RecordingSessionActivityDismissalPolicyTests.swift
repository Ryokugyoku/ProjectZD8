import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityDismissalPolicy` の終了表示の保持時間と消去時刻を確認します。
final class RecordingSessionActivityDismissalPolicyTests: XCTestCase {
    /// 責務: 保持時間が5分(300秒)であることを確認します。
    func testRetentionIsFiveMinutes() {
        XCTAssertEqual(RecordingSessionActivityDismissalPolicy.retention, 300)
    }

    /// 責務: 消去時刻が終了時刻の300秒後になることを確認します。
    func testDismissAtIsEndPlusRetention() {
        let endedAt = Date(timeIntervalSince1970: 1_700)
        XCTAssertEqual(
            RecordingSessionActivityDismissalPolicy.dismissAt(endedAt: endedAt),
            Date(timeIntervalSince1970: 2_000)
        )
    }

    /// 責務: 基準時刻が0や極端に古い場合でも、差が常に保持時間になることを確認します。
    func testDismissAtOffsetIsConstant() {
        for seconds in [0.0, -100, 1e9] {
            let endedAt = Date(timeIntervalSince1970: seconds)
            XCTAssertEqual(
                RecordingSessionActivityDismissalPolicy.dismissAt(endedAt: endedAt).timeIntervalSince(endedAt), 300
            )
        }
    }
}
