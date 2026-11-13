#if os(macOS)
import CoreGraphics

/// macOSログイン画面のウインドウ寸法に応じた表示規則です。
struct MacOSLoginMetrics: Equatable {
    /// 基準ウインドウに対する内部コンテンツ倍率です。
    let scale: CGFloat

    /// 横並びを縦積みへ切り替えるかどうかです。
    let usesStackedLayout: Bool

    /// 画面外周の余白です。
    let outerPadding: CGFloat

    /// コックピット意匠の直径です。
    let heroDiameter: CGFloat

    /// 認証パネルの最大幅です。
    let panelMaxWidth: CGFloat

    /// 利用可能ウインドウ寸法と文字拡大状態からmacOS専用表示規則を解決します。
    ///
    /// 責務: 1件のmacOS表示領域を最小ウインドウでも操作可能なログイン寸法へ変換します。
    /// - Parameters:
    ///   - size: ウインドウ内で利用可能な表示領域。
    ///   - usesAccessibilityText: アクセシビリティ文字サイズを使用しているかどうか。
    /// - Returns: macOSログイン画面のレスポンシブ表示規則。
    static func resolve(size: CGSize, usesAccessibilityText: Bool) -> MacOSLoginMetrics {
        let dimensionScale = min(size.width / 1200, size.height / 800)
        let scale = min(max(dimensionScale, 0.82), 1.35)
        let stacked = size.width < 820 || size.height < 560 || usesAccessibilityText
        return MacOSLoginMetrics(
            scale: scale,
            usesStackedLayout: stacked,
            outerPadding: max(18, 34 * scale),
            heroDiameter: (stacked ? 150 : 260) * scale,
            panelMaxWidth: min(max(size.width * (stacked ? 0.84 : 0.36), 360), 520)
        )
    }
}
#endif
