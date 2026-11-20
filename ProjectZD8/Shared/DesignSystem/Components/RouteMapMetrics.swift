import CoreGraphics

/// 地図部品 `RouteMapView` の寸法と表示範囲の決まりを集約します。機能の知識を持たない汎用の値です。
enum RouteMapMetrics {
    /// 線の既定の太さ(pt)です。呼び出し側が `RouteMapLineAppearance` を作る時に使います。
    static let lineWidth: CGFloat = 5
    /// 縁取りの線が本体の線より太い分(pt。両側の合計)です。
    static let casingExtraWidth: CGFloat = 2.5
    /// 端の印(始点・終点)の直径(pt)です。
    static let markerDiameter: CGFloat = 22
    /// 連動の印の直径(pt)です。
    static let focusDiameter: CGFloat = 18
    /// 端の印の中の記号の大きさの、印の直径に対する割合です。
    static let markerSymbolRatio: CGFloat = 0.5
    /// 端の印の白い縁の太さ(pt)です。
    static let markerBorderWidth: CGFloat = 2
    /// 連動の印のシアンの縁の太さ(pt)です。
    static let focusBorderWidth: CGFloat = 4
    /// 破線の線の長さと隙間(pt)です。
    static let dashPattern: [CGFloat] = [8, 7]
    /// 表示範囲の各辺に足す余白の、外接矩形の幅・高さに対する割合です。
    nonisolated static let boundsPaddingRatio: Double = 0.15
    /// 表示範囲の幅・高さの最小値(m)です。1点だけの時や極端に小さい範囲で過度に拡大しないために使います。
    nonisolated static let minimumSpanMeters: Double = 400
}
