#if os(iOS)
import CoreGraphics

/// iOSログイン画面の利用可能サイズに応じた表示寸法です。
struct IOSLoginMetrics: Equatable {
    /// コンテンツ左右の余白です。
    let horizontalPadding: CGFloat

    /// 中央コンテンツの最大幅です。
    let contentMaxWidth: CGFloat

    /// コックピット意匠の直径です。
    let heroDiameter: CGFloat

    /// 縦方向の主要要素間隔です。
    let sectionSpacing: CGFloat

    /// 高さが限られた端末向けのコンパクト構成かどうかです。
    let usesCompactHeight: Bool

    /// 利用可能サイズと文字拡大状態からiOS専用寸法を解決します。
    ///
    /// 責務: 1件のiOS表示領域を見切れないログイン画面寸法へ変換します。
    /// - Parameters:
    ///   - size: Safe Area内で利用可能な表示領域。
    ///   - usesAccessibilityText: アクセシビリティ文字サイズを使用しているかどうか。
    /// - Returns: iPhoneとiPadで使用するレスポンシブ表示寸法。
    static func resolve(size: CGSize, usesAccessibilityText: Bool) -> IOSLoginMetrics {
        let compactHeight = size.height < 700 || usesAccessibilityText
        let widthScale = min(max(size.width / 390, 0.88), 1.28)
        let horizontalPadding: CGFloat = size.width < 360 ? 18 : 24
        return IOSLoginMetrics(
            horizontalPadding: horizontalPadding,
            contentMaxWidth: min(max(size.width - (horizontalPadding * 2), 280), 620),
            heroDiameter: (compactHeight ? 156 : 206) * widthScale,
            sectionSpacing: compactHeight ? 20 : 30,
            usesCompactHeight: compactHeight
        )
    }
}
#endif
