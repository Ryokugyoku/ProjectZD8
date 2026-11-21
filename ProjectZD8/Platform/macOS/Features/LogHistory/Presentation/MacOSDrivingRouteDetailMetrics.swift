#if os(macOS)
import CoreGraphics

/// macOS のセッション詳細の走行ルートのカードと「大きく表示」のシートに使う表示寸法です。
///
/// いずれも `MacOSAppShellMetrics.scale` を掛けて使います。
enum MacOSDrivingRouteDetailMetrics {
    /// カード内側の余白です。
    static let cardPadding: CGFloat = 20
    /// カードの角丸半径です。
    static let cardCornerRadius: CGFloat = 24
    /// カードの中の地図と右の列の間隔、および見出しと状態の表示の間隔です。
    static let cardSpacing: CGFloat = 18
    /// カードの中の地図の高さです。
    static let mapHeight: CGFloat = 300
    /// 地図の右に置く列(見出し・要約・注記・操作)の幅です。
    static let sideColumnWidth: CGFloat = 260
    /// 地図の角丸半径です。
    static let mapCornerRadius: CGFloat = 18
    /// 要約の項目どうしの間隔です。
    static let summarySpacing: CGFloat = 12
    /// 要約の項目の見出しと値の間隔です。
    static let summaryLabelSpacing: CGFloat = 2
    /// 注記どうしの間隔です。
    static let noticeSpacing: CGFloat = 6
    /// 「大きく表示」のシートの幅です。
    static let sheetWidth: CGFloat = 960
    /// 「大きく表示」のシートの高さです。
    static let sheetHeight: CGFloat = 680
    /// シートの見出し・下端の帯の内側の余白です。
    static let sheetBarPadding: CGFloat = 16
    /// シートの下端の帯で、注記の列に許す最大の幅です。
    static let sheetNoticeMaxWidth: CGFloat = 390
    /// 読み込み中・理由・失敗の表示の最小の高さです。
    static let statusMinHeight: CGFloat = 140
    /// 読み込み中・理由・失敗の表示の中の要素の間隔です。
    static let statusSpacing: CGFloat = 10
    /// 理由・失敗のアイコンのフォントサイズです。
    static let statusIconFontSize: CGFloat = 26
    /// 理由・失敗・読み込み中の文言のフォントサイズです。
    static let statusMessageFontSize: CGFloat = 12
    /// 見出しのフォントサイズです。
    static let titleFontSize: CGFloat = 15
    /// 要約の項目の見出しのフォントサイズです。
    static let summaryLabelFontSize: CGFloat = 10
    /// 要約の項目の値のフォントサイズです。
    static let summaryValueFontSize: CGFloat = 16
    /// 注記のフォントサイズです。
    static let noticeFontSize: CGFloat = 10.5
    /// 列の中の見出し・要約・注記の間隔です。
    static let sideColumnSpacing: CGFloat = 14
}
#endif
