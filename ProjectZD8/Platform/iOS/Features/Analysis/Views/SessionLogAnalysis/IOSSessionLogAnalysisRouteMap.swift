#if os(iOS)
import SwiftUI

/// iPhone の解析の「ルート」の表示で、色分けした走行ルートと連動の印を、移動と拡大縮小のできる地図に描きます。
struct IOSSessionLogAnalysisRouteMap: View {
    /// 地図に描く線・端の印・表示範囲です。
    let layers: RouteAnalysisMapLayers
    /// 連動の印を置く座標です。グラフで時刻を選んでいない時・その時刻の位置が無い時は `nil` です。
    let focus: GeoCoordinate?

    /// 地図を描画します。
    ///
    /// 責務: 共有の地図部品へ線・印・範囲・連動の印を渡し、地図の高さと角丸を付けます(地図からの選択は受け取りません)。
    var body: some View {
        RouteMapView(
            lines: layers.lines,
            markers: layers.markers,
            bounds: layers.bounds,
            focus: focus,
            interaction: .explorable,
            accessibilityLabelKey: "history.route.map.accessibility"
        )
        .frame(height: IOSRouteAnalysisMetrics.mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: IOSRouteAnalysisMetrics.mapCornerRadius, style: .continuous))
        .accessibilityIdentifier("ios-analysis-route-map")
    }
}
#endif
