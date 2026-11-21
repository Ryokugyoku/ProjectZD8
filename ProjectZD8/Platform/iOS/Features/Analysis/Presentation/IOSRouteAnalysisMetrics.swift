#if os(iOS)
import CoreGraphics

/// iPhone の解析画面の「ルート」の表示(地図・凡例・読み出し・グラフ)の寸法です。
enum IOSRouteAnalysisMetrics {
    /// 地図の高さです。縦のスクロールと取り合わないよう低めに抑えます。
    static let mapHeight: CGFloat = 300
    /// 地図の角の半径です。
    static let mapCornerRadius: CGFloat = 16
    /// 指標のグラフの高さです。
    static let metricChartHeight: CGFloat = 180
    /// 標高のグラフの高さです。
    static let elevationChartHeight: CGFloat = 140
    /// 凡例の色見本の幅です。
    static let legendSwatchWidth: CGFloat = 18
    /// 凡例の色見本の高さです。
    static let legendSwatchHeight: CGFloat = 6
    /// 凡例の値なしの色見本の破線の線の長さと隙間(pt)です。
    static let legendSwatchDashPattern: [CGFloat] = [3, 2]
    /// 凡例の項目どうしの間隔と、色見本と文字の間隔です。
    static let legendSpacing: CGFloat = 8
    /// 凡例の1項目に確保する最小の幅です(横に折り返して並べます)。
    static let legendItemMinWidth: CGFloat = 120
    /// 読み出しの項目どうしの間隔です。
    static let readoutSpacing: CGFloat = 12
    /// カードの中の要素の縦の間隔です。
    static let cardSpacing: CGFloat = 13
    /// グラフの見出しとグラフの縦の間隔です。
    static let chartSpacing: CGFloat = 6
    /// 注記どうしの縦の間隔です。
    static let noticeSpacing: CGFloat = 6
    /// 読み込み中・理由・失敗の表示の最小の高さです(地図の場所に出します)。
    static let statusMinHeight: CGFloat = 160
    /// 読み込み中・理由・失敗の表示の中の要素の縦の間隔です。
    static let statusSpacing: CGFloat = 10
    /// 理由・失敗のアイコンの大きさです。
    static let statusIconSize: CGFloat = 28
    /// 色の段が1つ上がるごとに足す線の太さ(pt)です。
    static let rampWidthIncrement: CGFloat = 0.5
    /// 強調する時刻の範囲の線に足す太さ(pt)です。
    static let emphasizedExtraWidth: CGFloat = 2
    /// グラフの選んだ時刻の縦線の太さ(pt)です。
    static let selectionRuleWidth: CGFloat = 1
    /// グラフの強調する時刻の範囲の塗りの不透明度です。
    static let highlightOpacity: Double = 0.14
    /// グラフの線の太さ(pt)です。
    static let chartLineWidth: CGFloat = 2
}
#endif
