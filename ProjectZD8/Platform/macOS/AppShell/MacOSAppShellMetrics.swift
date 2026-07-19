#if os(macOS)
import CoreGraphics

/// 利用可能なウインドウサイズからmacOS AppShellの表示寸法を提供します。
struct MacOSAppShellMetrics: Equatable {
    /// タイポグラフィ、シンボル、余白、コントロールへ一貫して適用する倍率です。
    let scale: CGFloat

    /// サイドバー全体の幅です。
    let sidebarWidth: CGFloat

    /// サイドバー内側の水平方向余白です。
    let horizontalPadding: CGFloat

    /// サイドバー内側の垂直方向余白です。
    let verticalPadding: CGFloat

    /// 1件のナビゲーション行の高さです。
    let rowHeight: CGFloat

    /// ナビゲーション行の間隔です。
    let rowSpacing: CGFloat

    /// ナビゲーション行に表示するシンボルの大きさです。
    let symbolSize: CGFloat

    /// 遷移先プレースホルダーのタイトル文字サイズです。
    let contentTitleSize: CGFloat

    /// 遷移先プレースホルダーのシンボルサイズです。
    let contentSymbolSize: CGFloat

    /// 低いウインドウ向けにサイドバー補助情報を省略するかどうかです。
    let usesCompactSidebarHeight: Bool

    /// 指定した倍率からAppShellの表示寸法一式を生成します。
    ///
    /// 責務: 制限済みの倍率をmacOS AppShellの各表示寸法へ変換します。
    /// - Parameters:
    ///   - scale: 現在のウインドウに適用する制限済みの表示倍率。
    ///   - usesCompactSidebarHeight: サイドバーを低いウインドウ向けに縮約するかどうか。
    init(scale: CGFloat, usesCompactSidebarHeight: Bool = false) {
        self.scale = scale
        self.usesCompactSidebarHeight = usesCompactSidebarHeight
        sidebarWidth = 272 * scale
        horizontalPadding = 14 * scale
        verticalPadding = (usesCompactSidebarHeight ? 10 : 18) * scale
        rowHeight = (usesCompactSidebarHeight ? 48 : 62) * scale
        rowSpacing = (usesCompactSidebarHeight ? 3 : 7) * scale
        symbolSize = 20 * scale
        contentTitleSize = 32 * scale
        contentSymbolSize = 72 * scale
    }

    /// 利用可能な幅と高さから制限済みの表示倍率を解決します。
    ///
    /// 責務: 現在のウインドウ寸法からAppShell用の表示寸法一式を導出します。
    /// - Parameter size: macOSウインドウ内で利用可能な領域。
    /// - Returns: 制約の厳しい方の寸法へ追従する表示寸法。
    static func resolve(for size: CGSize) -> MacOSAppShellMetrics {
        let widthScale = size.width / 1_200
        let heightScale = size.height / 800
        let boundedScale = min(max(min(widthScale, heightScale), 0.82), 1.35)
        return MacOSAppShellMetrics(
            scale: boundedScale,
            usesCompactSidebarHeight: size.height < 560
        )
    }
}
#endif
