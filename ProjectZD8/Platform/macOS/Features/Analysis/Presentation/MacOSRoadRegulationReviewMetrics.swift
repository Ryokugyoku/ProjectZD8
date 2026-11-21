#if os(macOS)
import CoreGraphics

/// macOS の解析画面の「交通規制との照合」のカード(状態・注記・まとめ・切替・一覧・出典)の寸法です。
///
/// すべて `MacOSAppShellMetrics.scale` を掛けて使います。
enum MacOSRoadRegulationReviewMetrics {
    /// カードの中の要素の縦の間隔です。
    static let sectionSpacing: CGFloat = 16
    /// まとめのタイルの列の数です。
    static let summaryColumns = 4
    /// まとめのタイルどうしの間隔です。
    static let summaryTileSpacing: CGFloat = 10
    /// まとめのタイルの内側の余白です。
    static let summaryTilePadding: CGFloat = 14
    /// まとめのタイルの角丸半径です。
    static let summaryTileCornerRadius: CGFloat = 16
    /// 一覧の行どうしの間隔です。
    static let rowSpacing: CGFloat = 8
    /// 一覧の行の内側の余白です。
    static let rowPadding: CGFloat = 12
    /// 一覧の行の角丸半径です。
    static let rowCornerRadius: CGFloat = 14
    /// 色見本の直径です。
    static let swatchSize: CGFloat = 11
    /// 状態の表示の最小の高さです。
    static let statusMinHeight: CGFloat = 140
    /// 出典と注意書きの行どうしの間隔です。
    static let attributionSpacing: CGFloat = 5
    /// 状態の表示・注記・タイルの中の要素の間隔です。
    static let contentSpacing: CGFloat = 6
    /// 状態の表示のアイコンの大きさです。
    static let statusIconFontSize: CGFloat = 22
    /// 状態の表示の文言の大きさです。
    static let statusMessageFontSize: CGFloat = 12
    /// 種類の見出しとタイルの種類名の文字の大きさです。
    static let kindTitleFontSize: CGFloat = 13
    /// 行の判定の文言の大きさです。
    static let rowTitleFontSize: CGFloat = 13
    /// 行の時刻・数値、注記、タイルの件数、出典の文字の大きさです。
    static let captionFontSize: CGFloat = 11
    /// 行のアイコンの大きさです。
    static let rowIconFontSize: CGFloat = 14
    /// 行とタイルの枠線の太さです。
    static let borderWidth: CGFloat = 1
    /// 選ばれている行の枠線の太さです。
    static let selectedBorderWidth: CGFloat = 2
    /// 行とタイルの背景の塗りの不透明度です。
    static let fillOpacity: Double = 0.04
    /// 行とタイルの枠線の不透明度です。
    static let borderOpacity: Double = 0.07
}
#endif
