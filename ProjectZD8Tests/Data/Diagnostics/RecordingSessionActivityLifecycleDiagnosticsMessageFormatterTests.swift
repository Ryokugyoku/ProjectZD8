import XCTest
@testable import ProjectZD8

/// 記録中表示の状態遷移の診断文言が、実機テスト手順書が参照する固定文字列と完全一致することを検証します。
@MainActor
final class RecordingSessionActivityLifecycleDiagnosticsMessageFormatterTests: XCTestCase {
    /// テスト対象の整形器です。
    private let formatter = RecordingSessionActivityLifecycleDiagnosticsMessageFormatter()

    /// 表示の開始・終了・システムによる終了の文言を確認します。
    ///
    /// 責務: 表示の状態遷移の3つの文字列を確認します。
    func testActivityMessages() {
        XCTAssertEqual(formatter.started(), "Live Activity started")
        XCTAssertEqual(formatter.ended(), "Live Activity ended")
        XCTAssertEqual(formatter.closedBySystem(), "Live Activity closed by system")
    }

    /// [切断]の要求の受付と拒否の文言を確認します。
    ///
    /// 責務: 停止要求の2つの文字列を確認します。
    func testStopRequestMessages() {
        XCTAssertEqual(formatter.stopRequestAccepted(), "Live Activity stop requested: accepted")
        XCTAssertEqual(formatter.stopRequestDeclined(), "Live Activity stop requested: declined")
    }
}
