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

    /// iPhone縦向きで一列構成かつ認証パネルを下部固定にすることを検証します。
    ///
    /// 責務: 一般的なiPhone表示領域でログイン操作が常に届く構成になることを確認します。
    func testPortraitPhoneDocksAuthenticationPanel() {
        let metrics = IOSLoginMetrics.resolve(
            size: CGSize(width: 393, height: 759),
            usesAccessibilityText: false
        )

        XCTAssertEqual(metrics.layout, .singleColumn)
        XCTAssertTrue(metrics.docksAuthenticationPanel)
        XCTAssertEqual(metrics.capabilityColumnCount, 3)
    }

    /// iPhone横向きが二列構成になり、両列が表示幅に収まることを検証します。
    ///
    /// 責務: 高さの少ない横長表示を左右分割構成へ変換することを確認します。
    func testLandscapePhoneUsesSplitLayoutWithinWidth() {
        let size = CGSize(width: 734, height: 372)
        let metrics = IOSLoginMetrics.resolve(size: size, usesAccessibilityText: false)

        XCTAssertEqual(metrics.layout, .split)
        XCTAssertFalse(metrics.docksAuthenticationPanel)
        XCTAssertLessThanOrEqual(
            (metrics.horizontalPadding * 2) + metrics.contentMaxWidth + metrics.columnSpacing + metrics.panelWidth,
            size.width
        )
        XCTAssertLessThanOrEqual(metrics.heroDiameter, size.height * 0.4)
    }

    /// iPad縦向きが中央一列構成で、意匠が上限寸法に収まることを検証します。
    ///
    /// 責務: 縦長の大画面を読みやすい幅の一列構成へ変換することを確認します。
    func testPortraitPadUsesCenteredSingleColumn() {
        let metrics = IOSLoginMetrics.resolve(
            size: CGSize(width: 820, height: 1140),
            usesAccessibilityText: false
        )

        XCTAssertEqual(metrics.layout, .singleColumn)
        XCTAssertFalse(metrics.docksAuthenticationPanel)
        XCTAssertLessThanOrEqual(metrics.contentMaxWidth, 560)
        XCTAssertLessThanOrEqual(metrics.heroDiameter, 280)
    }

    /// iPad横向きが二列構成で大型見出しを使うことを検証します。
    ///
    /// 責務: 広い横長表示をショーケースと認証パネルの二列へ変換することを確認します。
    func testLandscapePadUsesSplitLayoutWithDisplayTitle() {
        let metrics = IOSLoginMetrics.resolve(
            size: CGSize(width: 1180, height: 800),
            usesAccessibilityText: false
        )

        XCTAssertEqual(metrics.layout, .split)
        XCTAssertTrue(metrics.usesDisplayTitle)
        XCTAssertLessThanOrEqual(metrics.panelWidth, 440)
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
        XCTAssertEqual(metrics.layout, .singleColumn)
        XCTAssertFalse(metrics.docksAuthenticationPanel)
        XCTAssertEqual(metrics.capabilityColumnCount, 1)
    }
}
#endif
