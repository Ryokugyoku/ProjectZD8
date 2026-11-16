#if os(macOS)
import CoreGraphics

/// macOS設定画面の「エンジン停止の判定時間」カードに使う表示寸法です。いずれも `MacOSAppShellMetrics.scale` を掛けて使います。
enum MacOSSettingsVehicleOffMetrics {
    /// 見出しと操作領域の間隔です。
    static let cardSpacing: CGFloat = 16
    /// 見出しのアイコンと文言の間隔です。
    static let headerSpacing: CGFloat = 12
    /// 見出し内の文言の行間隔です。
    static let textSpacing: CGFloat = 3
    /// 見出しのアイコン枠の一辺です。
    static let iconSize: CGFloat = 34
    /// 見出しのアイコン枠の角丸半径です。
    static let iconCornerRadius: CGFloat = 10
    /// 見出しのアイコンのフォントサイズです。
    static let iconFontSize: CGFloat = 16
    /// 種別表示のフォントサイズです。
    static let eyebrowFontSize: CGFloat = 9
    /// 種別表示の文字間隔です。
    static let eyebrowTracking: CGFloat = 1.2
    /// タイトルのフォントサイズです。
    static let titleFontSize: CGFloat = 17
    /// 説明のフォントサイズです。
    static let descriptionFontSize: CGFloat = 11.5
    /// カード内側の余白です。
    static let cardPadding: CGFloat = 18
    /// カードの角丸半径です。
    static let cardCornerRadius: CGFloat = 20
}
#endif
