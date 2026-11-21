#if os(macOS)
import CoreGraphics

/// macOSの交通規制データの管理画面と設定カードに使う表示寸法です。いずれも `MacOSAppShellMetrics.scale` を掛けて使います。
enum MacOSRoadRegulationDataMetrics {
    /// シートの最小の幅です。
    static let sheetMinWidth: CGFloat = 560
    /// シートの望ましい幅です。
    static let sheetIdealWidth: CGFloat = 660
    /// シートの最小の高さです。
    static let sheetMinHeight: CGFloat = 520
    /// シートの望ましい高さです。
    static let sheetIdealHeight: CGFloat = 680
    /// シートの見出しの内側の余白です。
    static let headerPadding: CGFloat = 20
    /// シートの見出しの要素の間隔です。
    static let headerSpacing: CGFloat = 14
    /// シートの見出しのアイコン枠の一辺です。
    static let headerIconSize: CGFloat = 42
    /// シートの見出しのアイコン枠の角丸半径です。
    static let headerIconCornerRadius: CGFloat = 12
    /// シートの見出しのアイコンのフォントサイズです。
    static let headerIconFontSize: CGFloat = 19
    /// シートの見出しのアイコン枠の背景の不透明度です。
    static let headerIconFillOpacity: Double = 0.14
    /// シートの見出しのタイトルのフォントサイズです。
    static let headerTitleFontSize: CGFloat = 19
    /// 都道府県の行の中の要素の間隔です。
    static let rowSpacing: CGFloat = 7
    /// 都道府県の行の上下の余白です。
    static let rowVerticalPadding: CGFloat = 5
    /// 都道府県名と状態の間隔です。
    static let rowTitleSpacing: CGFloat = 8
    /// 都道府県名のフォントサイズです。
    static let rowTitleFontSize: CGFloat = 13
    /// 補助の文字(詳細・段階・失敗)のフォントサイズです。
    static let captionFontSize: CGFloat = 11
    /// 版の詳細の項目同士の間隔です。
    static let detailSpacing: CGFloat = 12
    /// 行のボタン同士の間隔です。
    static let buttonSpacing: CGFloat = 8
    /// 状態のバッジのフォントサイズです。
    static let badgeFontSize: CGFloat = 10
    /// 状態のバッジの左右の余白です。
    static let badgeHorizontalPadding: CGFloat = 7
    /// 状態のバッジの上下の余白です。
    static let badgeVerticalPadding: CGFloat = 2
    /// 状態のバッジの背景の不透明度です。
    static let badgeFillOpacity: Double = 0.12
    /// 進み具合の表示の要素の間隔です。
    static let progressSpacing: CGFloat = 4
    /// 「更新を確認」の欄・出典の欄の要素の間隔です。
    static let sectionSpacing: CGFloat = 8
    /// 設定カードの中の要素の間隔です。
    static let cardContentSpacing: CGFloat = 10
    /// 設定カードのまとめのフォントサイズです。
    static let cardSummaryFontSize: CGFloat = 11.5
}
#endif
