#if os(iOS)
import CoreGraphics
import XCTest
@testable import ProjectZD8

/// iOSログイン画面のレスポンシブ寸法規則を検証します。
final class IOSLoginMetricsTests: XCTestCase {
    /// 小さいiPhone幅でもコンテンツと余白が表示領域内に収まることを検証します。
    ///
    /// 責務: 狭いiPhone表示領域が最小操作幅を保つ寸法へ解決されることを確認します。
    func testNarrowPhoneMetricsRemainWithinAvailableWidth() {
        let metrics = IOSLoginMetrics.resolve(
            size: CGSize(width: 320, height: 568),
            usesAccessibilityText: false
        )

        XCTAssertLessThanOrEqual(
            metrics.contentMaxWidth + (metrics.horizontalPadding * 2),
            320
        )
        XCTAssertTrue(metrics.usesCompactHeight)
        XCTAssertGreaterThanOrEqual(metrics.horizontalPadding, 18)
    }

    /// アクセシビリティ文字サイズがコンパクト高さ構成を要求することを検証します。
    ///
    /// 責務: 文字拡大状態をスクロール前提のiOSコンパクト構成へ変換します。
    func testAccessibilityTextUsesCompactLayout() {
        let metrics = IOSLoginMetrics.resolve(
            size: CGSize(width: 430, height: 932),
            usesAccessibilityText: true
        )

        XCTAssertTrue(metrics.usesCompactHeight)
    }
}
#endif
