import XCTest
@testable import ProjectZD8

/// `BLEAdapterLinkLimits` の既定値と負の値の丸めを検証します。
final class BLEAdapterLinkLimitsTests: XCTestCase {
    /// 既定値は再接続5回・探索段階10秒です。
    ///
    /// 責務: 文書化された既定値を確認します。
    func testStandardValues() {
        XCTAssertEqual(BLEAdapterLinkLimits.standard.maximumConsecutiveReconnects, 5)
        XCTAssertEqual(BLEAdapterLinkLimits.standard.discoveryStepTimeout, .seconds(10))
    }

    /// 負の値は0へ丸められます。
    ///
    /// 責務: 回数と時間の両方の負値が0になることを確認します。
    func testNegativeValuesAreClampedToZero() {
        let limits = BLEAdapterLinkLimits(maximumConsecutiveReconnects: -1, discoveryStepTimeout: .seconds(-2))
        XCTAssertEqual(limits.maximumConsecutiveReconnects, 0)
        XCTAssertEqual(limits.discoveryStepTimeout, .zero)
    }

    /// 0と正の値はそのまま保持されます。
    ///
    /// 責務: 境界の0と通常値が変わらないことを確認します。
    func testZeroAndPositiveValuesArePreserved() {
        let zero = BLEAdapterLinkLimits(maximumConsecutiveReconnects: 0, discoveryStepTimeout: .zero)
        XCTAssertEqual(zero.maximumConsecutiveReconnects, 0)
        XCTAssertEqual(zero.discoveryStepTimeout, .zero)
        let positive = BLEAdapterLinkLimits(maximumConsecutiveReconnects: 3, discoveryStepTimeout: .milliseconds(250))
        XCTAssertEqual(positive.maximumConsecutiveReconnects, 3)
        XCTAssertEqual(positive.discoveryStepTimeout, .milliseconds(250))
    }
}
