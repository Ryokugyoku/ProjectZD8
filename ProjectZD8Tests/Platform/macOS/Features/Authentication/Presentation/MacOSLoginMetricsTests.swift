#if os(macOS)
import CoreGraphics
import XCTest
@testable import ProjectZD8

/// macOSログイン画面のウインドウ追従規則を検証します。
final class MacOSLoginMetricsTests: XCTestCase {
    /// 640×420の最小ウインドウが操作可能な縦積み構成になることを検証します。
    ///
    /// 責務: macOS最小ウインドウを縮小下限付きの一列構成へ変換します。
    func testMinimumWindowUsesStackedLayoutAndScaleFloor() {
        let metrics = MacOSLoginMetrics.resolve(
            size: CGSize(width: 640, height: 420),
            usesAccessibilityText: false
        )

        XCTAssertTrue(metrics.usesStackedLayout)
        XCTAssertEqual(metrics.scale, 0.82, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(metrics.panelWidth, 360)
        XCTAssertLessThanOrEqual(metrics.contentMaxWidth + (metrics.outerPadding * 2), 640)
    }

    /// 大きいウインドウでコンテンツ倍率が上限を超えないことを検証します。
    ///
    /// 責務: macOS拡大ウインドウの内部表示倍率を視認性上限へ制限します。
    func testLargeWindowCapsContentScale() {
        let metrics = MacOSLoginMetrics.resolve(
            size: CGSize(width: 2400, height: 1600),
            usesAccessibilityText: false
        )

        XCTAssertFalse(metrics.usesStackedLayout)
        XCTAssertEqual(metrics.scale, 1.35, accuracy: 0.001)
        XCTAssertLessThanOrEqual(metrics.panelWidth, 460)
    }

    /// 標準ウインドウで二列構成に収まり、意匠が見出しの横へ並ぶことを検証します。
    ///
    /// 責務: 既定ウインドウ寸法の全列幅がウインドウ内に収まることを確認します。
    func testDefaultWindowUsesSplitLayoutWithinWidth() {
        let size = CGSize(width: 1200, height: 800)
        let metrics = MacOSLoginMetrics.resolve(size: size, usesAccessibilityText: false)

        XCTAssertEqual(metrics.layout, .split)
        XCTAssertTrue(metrics.placesHeroBesideIntroduction)
        XCTAssertLessThanOrEqual(
            (metrics.outerPadding * 2) + metrics.contentMaxWidth + metrics.columnSpacing + metrics.panelWidth,
            size.width
        )
    }

    /// 横幅はあるが低いウインドウで縦積みに切り替わることを検証します。
    ///
    /// 責務: 高さ不足のウインドウをスクロール可能な一列構成へ変換することを確認します。
    func testShortWideWindowUsesSingleColumn() {
        let metrics = MacOSLoginMetrics.resolve(
            size: CGSize(width: 1100, height: 480),
            usesAccessibilityText: false
        )

        XCTAssertEqual(metrics.layout, .singleColumn)
    }

    /// アクセシビリティ文字サイズで横長ウインドウも縦積みになることを検証します。
    ///
    /// 責務: 文字拡大状態をmacOSの見切れにくい一列構成へ変換します。
    func testAccessibilityTextForcesStackedLayout() {
        let metrics = MacOSLoginMetrics.resolve(
            size: CGSize(width: 1200, height: 800),
            usesAccessibilityText: true
        )

        XCTAssertTrue(metrics.usesStackedLayout)
    }
}
#endif
