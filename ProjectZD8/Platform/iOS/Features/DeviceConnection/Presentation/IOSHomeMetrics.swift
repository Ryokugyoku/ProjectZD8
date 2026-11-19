#if os(iOS)
import CoreGraphics

/// iOSホームの表示寸法です。
enum IOSHomeMetrics {
    /// 画面要素どうしの縦方向の間隔です。
    static let sectionSpacing: CGFloat = 22
    /// 通常の文字サイズでの画面左右の余白です。
    static let horizontalPadding: CGFloat = 20
    /// アクセシビリティ用の大きな文字サイズでの画面左右の余白です。
    static let accessibilityHorizontalPadding: CGFloat = 16
    /// 画面上端の余白です。
    static let topPadding: CGFloat = 16
    /// 画面下端の余白です。
    static let bottomPadding: CGFloat = 28

    /// ブランドの記号枠の一辺です。
    static let brandIconSize: CGFloat = 46
    /// ブランドの記号枠の角丸半径です。
    static let brandIconCornerRadius: CGFloat = 14
    /// ブランドの記号の大きさです。
    static let brandIconFontSize: CGFloat = 20
    /// ブランドの標語の文字サイズです。
    static let brandTaglineFontSize: CGFloat = 10

    /// アダプターカードの内側の余白です。
    static let cardPadding: CGFloat = 20
    /// アダプターカードの角丸半径です。
    static let cardCornerRadius: CGFloat = 28
    /// カードの枠線の不透明度です。
    static let cardStrokeOpacity: Double = 0.18
    /// カードの影の不透明度です。
    static let cardShadowOpacity: Double = 0.08
    /// カードの影のぼかし半径です。
    static let cardShadowRadius: CGFloat = 18
    /// カードの影の縦方向のずれです。
    static let cardShadowOffsetY: CGFloat = 8

    /// アダプターの記号枠の一辺です。
    static let adapterSymbolSize: CGFloat = 72
    /// アダプターの記号の大きさです。
    static let adapterSymbolFontSize: CGFloat = 28

    /// セッション見出しの内側の余白です。
    static let sessionHeaderPadding: CGFloat = 18
    /// セッション見出しの角丸半径です。
    static let sessionHeaderCornerRadius: CGFloat = 24
    /// セッション見出しの記録中の印の一辺です。
    static let recordingIndicatorSize: CGFloat = 9
}
#endif
