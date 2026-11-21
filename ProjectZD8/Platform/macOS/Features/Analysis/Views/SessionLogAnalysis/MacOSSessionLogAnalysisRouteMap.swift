#if os(macOS)
import SwiftUI

/// macOS の解析の「ルート」の表示で、色分けした走行ルートと連動の印を、移動と拡大縮小のできる地図に描きます。
struct MacOSSessionLogAnalysisRouteMap: View {
    /// 地図に描く線・端の印・表示範囲です。
    let layers: RouteAnalysisMapLayers
    /// 連動の印を置く座標です。グラフで時刻を選んでいない時・その時刻の位置が無い時は `nil` です。
    let focus: GeoCoordinate?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

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
        .frame(height: MacOSRouteAnalysisMetrics.mapHeight * scale)
        .clipShape(RoundedRectangle(cornerRadius: MacOSRouteAnalysisMetrics.mapCornerRadius * scale, style: .continuous))
        .accessibilityIdentifier("macos-analysis-route-map")
    }
}
#endif
