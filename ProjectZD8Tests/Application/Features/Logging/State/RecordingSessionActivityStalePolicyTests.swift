import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityStalePolicy` の表示の有効期限(更新が途絶えてから「古い」扱いになるまでの時間と時刻)を確認します。
///
/// 仕様: S2-1。有効期限は開始・更新を受け付けた時刻のちょうど60秒後です。
final class RecordingSessionActivityStalePolicyTests: XCTestCase {
    /// 責務: 有効期限までの間隔が60秒であることを確認します。
    func testStaleIntervalIsSixtySeconds() {
        XCTAssertEqual(RecordingSessionActivityStalePolicy.staleInterval, 60)
    }

    /// 責務: 有効期限が更新時刻のちょうど60秒後(59秒や61秒ではない)になることを確認します。
    func testStaleDateIsExactlyIntervalAfterUpdate() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let staleDate = RecordingSessionActivityStalePolicy.staleDate(updatedAt: updatedAt)
        XCTAssertEqual(staleDate, Date(timeIntervalSince1970: 1_060))
        XCTAssertNotEqual(staleDate, Date(timeIntervalSince1970: 1_059))
        XCTAssertNotEqual(staleDate, Date(timeIntervalSince1970: 1_061))
    }

    /// 責務: 更新時刻が0・負・非常に大きい・小数でも、更新時刻との差が常に60秒になることを確認します。
    func testStaleDateOffsetIsConstant() {
        for seconds in [0.0, -100, 1e9, 1_234.5] {
            let updatedAt = Date(timeIntervalSince1970: seconds)
            XCTAssertEqual(
                RecordingSessionActivityStalePolicy.staleDate(updatedAt: updatedAt).timeIntervalSince(updatedAt), 60,
                "更新時刻 \(seconds)"
            )
        }
    }

    /// 責務: 更新時刻が後になれば有効期限も同じだけ後になる(前回の期限を引き継がない)ことを確認します。
    func testLaterUpdateGivesLaterStaleDate() {
        let first = RecordingSessionActivityStalePolicy.staleDate(updatedAt: Date(timeIntervalSince1970: 1_000))
        let second = RecordingSessionActivityStalePolicy.staleDate(updatedAt: Date(timeIntervalSince1970: 1_003))
        XCTAssertEqual(second.timeIntervalSince(first), 3)
    }
}
