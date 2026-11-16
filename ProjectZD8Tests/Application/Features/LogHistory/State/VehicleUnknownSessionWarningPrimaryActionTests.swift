import XCTest
@testable import ProjectZD8

/// `VehicleUnknownSessionWarningPrimaryAction` の表示名キーと記号名を検証します。
final class VehicleUnknownSessionWarningPrimaryActionTests: XCTestCase {
    /// 一覧を開く操作と再読み込みは、別の表示名キーです。
    ///
    /// 責務: `titleKey` の2分岐を確認します。
    func testTitleKey() {
        XCTAssertEqual(VehicleUnknownSessionWarningPrimaryAction.reviewSessions.titleKey, "vehicle_unknown.warning.action.review")
        XCTAssertEqual(VehicleUnknownSessionWarningPrimaryAction.retryLoading.titleKey, "unassigned_vin.warning.action.retry")
    }

    /// 操作ごとに空でない別の記号名を返します。
    ///
    /// 責務: `systemImageName` の2分岐が空でなく互いに異なることを確認します。
    func testSystemImageName() {
        let review = VehicleUnknownSessionWarningPrimaryAction.reviewSessions.systemImageName
        let retry = VehicleUnknownSessionWarningPrimaryAction.retryLoading.systemImageName
        XCTAssertFalse(review.isEmpty)
        XCTAssertFalse(retry.isEmpty)
        XCTAssertNotEqual(review, retry)
    }
}
