#if os(macOS)
import CoreGraphics

/// macOS の解析画面の「ルート」の表示(色分けのチップ・地図・凡例・読み出し・グラフ)の寸法です。
///
/// 地図の線の太さ(`rampWidthIncrement`、`emphasizedExtraWidth`)以外は `MacOSAppShellMetrics.scale` を掛けて使います。
enum MacOSRouteAnalysisMetrics {
    /// 地図の高さです。
    static let mapHeight: CGFloat = 420
    /// 地図の角丸半径です。
    static let mapCornerRadius: CGFloat = 18
    /// 指標のグラフの高さです。
    static let metricChartHeight: CGFloat = 220
    /// 標高のグラフの高さです。
    static let elevationChartHeight: CGFloat = 160
    /// 色分けのチップどうしの間隔です。
    static let chipSpacing: CGFloat = 8
    /// 色分けのチップの高さです。
    static let chipHeight: CGFloat = 28
    /// 色分けのチップの左右の内側の余白です。
    static let chipHorizontalPadding: CGFloat = 12
    /// 色分けのチップの文字の大きさです。
    static let chipFontSize: CGFloat = 12
    /// 凡例の色見本の幅です。
    static let legendSwatchWidth: CGFloat = 20
    /// 凡例の色見本の高さです。
    static let legendSwatchHeight: CGFloat = 7
    /// 凡例の値なしの色見本の破線の線の長さと隙間です。
    static let legendSwatchDashPattern: [CGFloat] = [3, 2]
    /// 凡例の項目どうしの間隔と、色見本と文字の間隔です。
    static let legendSpacing: CGFloat = 8
    /// 凡例の1項目に確保する最小の幅です(横に折り返して並べます)。
    static let legendItemMinWidth: CGFloat = 150
    /// 読み出しの項目どうしの間隔です。
    static let readoutSpacing: CGFloat = 16
    /// 読み出しの文字の大きさです。
    static let readoutFontSize: CGFloat = 13
    /// カードの中の要素の縦の間隔です。
    static let cardSpacing: CGFloat = 14
    /// グラフの見出しとグラフの縦の間隔です。
    static let chartSpacing: CGFloat = 6
    /// 注記どうしの縦の間隔です。
    static let noticeSpacing: CGFloat = 6
    /// 注記・案内の文字の大きさです。
    static let noticeFontSize: CGFloat = 11
    /// 読み込み中・理由・失敗の表示の最小の高さです(地図の場所に出します)。
    static let statusMinHeight: CGFloat = 200
    /// 読み込み中・理由・失敗の表示の中の要素の間隔です。
    static let statusSpacing: CGFloat = 10
    /// 理由・失敗のアイコンの大きさです。
    static let statusIconFontSize: CGFloat = 26
    /// 理由・失敗・読み込み中の文言の大きさです。
    static let statusMessageFontSize: CGFloat = 12
    /// 色の段が1つ上がるごとに足す地図の線の太さ(pt。倍率は掛けません)です。
    static let rampWidthIncrement: CGFloat = 0.5
    /// 強調する時刻の範囲の地図の線に足す太さ(pt。倍率は掛けません)です。
    static let emphasizedExtraWidth: CGFloat = 2
    /// グラフの選んだ時刻の縦線の太さです。
    static let selectionRuleWidth: CGFloat = 1
    /// グラフの強調する時刻の範囲の塗りの不透明度です。
    static let highlightOpacity: Double = 0.14
    /// グラフの線の太さです。
    static let chartLineWidth: CGFloat = 2
}
#endif
