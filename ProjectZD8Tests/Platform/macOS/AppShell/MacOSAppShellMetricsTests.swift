#if os(macOS)
import CoreGraphics
import XCTest
@testable import ProjectZD8

/// macOS AppShellのサイドバー高さ追従規則を検証します。
final class MacOSAppShellMetricsTests: XCTestCase {
    /// 640×420で5件のナビゲーションを優先するコンパクト寸法になることを検証します。
    ///
    /// 責務: 最小ウインドウを補助情報省略済みのサイドバー寸法へ変換することを確認します。
    func testMinimumWindowUsesCompactSidebarHeight() {
        let metrics = MacOSAppShellMetrics.resolve(for: CGSize(width: 640, height: 420))

        XCTAssertTrue(metrics.usesCompactSidebarHeight)
        XCTAssertLessThan(metrics.rowHeight, 40)
    }

    /// 1,200×800で補助文とフッターを保持する通常寸法になることを検証します。
    ///
    /// 責務: 参照ウインドウが情報量を省略しないサイドバー寸法になることを確認します。
    func testReferenceWindowKeepsExpandedSidebar() {
        let metrics = MacOSAppShellMetrics.resolve(for: CGSize(width: 1_200, height: 800))

        XCTAssertFalse(metrics.usesCompactSidebarHeight)
        XCTAssertEqual(metrics.rowHeight, 62, accuracy: 0.001)
    }
}
#endif
