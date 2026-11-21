import CoreLocation
import MapKit
import SwiftUI

/// 線・端の印・連動の印を MapKit の地図に描く、機能の知識を持たない汎用の地図部品です。
///
/// 表示範囲は `bounds` が変わった時だけ作り直し、連動の印 `focus` が動いてもカメラは動かしません。
/// 現在地は表示しないため、位置情報の許可は求めません。
struct RouteMapView<Line: RouteMapLineContent, Marker: RouteMapMarkerContent>: View {
    /// 縁取りの線の色です。どの線の色・地図の配色の上でも線の輪郭が分かるように白にします。
    private static var casingColor: Color { Color.white.opacity(0.9) }

    /// 描く線の列です。後ろの線ほど上に描きます。
    let lines: [Line]
    /// 端の印(始点・終点)の列です。
    let markers: [Marker]
    /// 表示する範囲の外接矩形です。`nil` なら地図の自動の範囲にします。
    let bounds: GeoBoundingBox?
    /// 連動の印を置く座標です。`nil` なら印を出しません。
    let focus: GeoCoordinate?
    /// 利用者に許す操作です。
    let interaction: RouteMapInteraction
    /// 地図全体に付けるアクセシビリティラベルのローカライズキーです。
    let accessibilityLabelKey: String
    /// 地図のタップを座標で受け取る操作です。`nil` 以外の時だけタップを座標へ直します。
    var onCoordinateSelected: ((GeoCoordinate) -> Void)?

    /// 地図のカメラの位置です。`bounds` から作ります。
    @State private var position: MapCameraPosition

    /// 地図に描く内容と操作の可否を受け取って作ります。
    ///
    /// 責務: 受け取った値を保持し、`bounds` からカメラの初期位置を決めます。
    /// - Parameters:
    ///   - lines: 描く線の列。
    ///   - markers: 端の印の列。
    ///   - bounds: 表示する範囲。`nil` なら自動。
    ///   - focus: 連動の印の座標。
    ///   - interaction: 利用者に許す操作。
    ///   - accessibilityLabelKey: 地図のアクセシビリティラベルのローカライズキー。
    ///   - onCoordinateSelected: 地図のタップを座標で受け取る操作。
    init(
        lines: [Line],
        markers: [Marker],
        bounds: GeoBoundingBox?,
        focus: GeoCoordinate?,
        interaction: RouteMapInteraction,
        accessibilityLabelKey: String,
        onCoordinateSelected: ((GeoCoordinate) -> Void)? = nil
    ) {
        self.lines = lines
        self.markers = markers
        self.bounds = bounds
        self.focus = focus
        self.interaction = interaction
        self.accessibilityLabelKey = accessibilityLabelKey
        self.onCoordinateSelected = onCoordinateSelected
        _position = State(initialValue: Self.cameraPosition(for: bounds))
    }

    /// 地図を描画します。
    ///
    /// 責務: タップの受け取りがある時だけ `MapReader` で包み、範囲の変化でカメラを作り直し、ラベルを付けます。
    var body: some View {
        Group {
            if let onCoordinateSelected {
                MapReader { proxy in
                    map.onTapGesture { location in
                        guard let coordinate = proxy.convert(location, from: .local),
                              let selected = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        else { return }
                        onCoordinateSelected(selected)
                    }
                }
            } else {
                map
            }
        }
        .onChange(of: bounds) { _, newBounds in
            position = Self.cameraPosition(for: newBounds)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(LocalizedStringKey(accessibilityLabelKey)))
    }

    /// 線と印を載せた地図です。
    ///
    /// 責務: 縁取り → 線 → 端の印 → 連動の印の順に重ね、地図の見た目と操作部品を設定します。
    private var map: some View {
        Map(position: $position, interactionModes: interactionModes) {
            ForEach(lines) { line in
                MapPolyline(coordinates: Self.mapCoordinates(line.coordinates))
                    .stroke(Self.casingColor, style: Self.strokeStyle(width: line.appearance.width + RouteMapMetrics.casingExtraWidth, isDashed: false))
            }
            ForEach(lines) { line in
                MapPolyline(coordinates: Self.mapCoordinates(line.coordinates))
                    .stroke(line.appearance.color, style: Self.strokeStyle(width: line.appearance.width, isDashed: line.appearance.isDashed))
            }
            ForEach(markers) { marker in
                Annotation("", coordinate: Self.mapCoordinate(marker.coordinate)) {
                    endpointMarker(marker.endpoint)
                }
                .annotationTitles(.hidden)
            }
            if let focus {
                Annotation("", coordinate: Self.mapCoordinate(focus)) {
                    focusMarker
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    /// 操作の可否に対応する地図の操作の種類です。
    ///
    /// 責務: `fixed` は操作なし、`explorable` は移動と拡大縮小に対応させます。
    private var interactionModes: MapInteractionModes {
        switch interaction {
        case .fixed: []
        case .explorable: [.pan, .zoom]
        }
    }

    /// 連動の印です。
    ///
    /// 責務: 白地にシアンの縁の円を描きます。
    private var focusMarker: some View {
        Circle()
            .fill(Color.white)
            .overlay { Circle().stroke(Color.cyan, lineWidth: RouteMapMetrics.focusBorderWidth) }
            .frame(width: RouteMapMetrics.focusDiameter, height: RouteMapMetrics.focusDiameter)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .accessibilityHidden(true)
    }

    /// 端の印を描きます。
    ///
    /// 責務: 色だけに頼らないよう、始点と終点で記号を変えた円の印を描きます。
    /// - Parameter endpoint: 始点か終点か。
    /// - Returns: 印の View。
    private func endpointMarker(_ endpoint: DrivingRouteEndpoint) -> some View {
        Image(systemName: Self.symbolName(for: endpoint))
            .font(.system(size: RouteMapMetrics.markerDiameter * RouteMapMetrics.markerSymbolRatio, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: RouteMapMetrics.markerDiameter, height: RouteMapMetrics.markerDiameter)
            .background(Self.markerColor(for: endpoint), in: Circle())
            .overlay { Circle().stroke(Color.white, lineWidth: RouteMapMetrics.markerBorderWidth) }
            .shadow(color: .black.opacity(0.3), radius: 2)
            .accessibilityHidden(true)
    }

    /// 端の印の記号名を返します。
    ///
    /// 責務: 始点は再生の記号、終点はチェッカーフラッグの記号に対応させます。
    /// - Parameter endpoint: 始点か終点か。
    /// - Returns: SF Symbols の名前。
    private static func symbolName(for endpoint: DrivingRouteEndpoint) -> String {
        switch endpoint {
        case .start: "play.fill"
        case .end: "flag.checkered"
        }
    }

    /// 端の印の地の色を返します。
    ///
    /// 責務: 始点はアクセントのシアン、終点は濃い灰色に対応させます。
    /// - Parameter endpoint: 始点か終点か。
    /// - Returns: 地の色。
    private static func markerColor(for endpoint: DrivingRouteEndpoint) -> Color {
        switch endpoint {
        case .start: Color.cyan
        case .end: Color(white: 0.2)
        }
    }

    /// 線の描き方を返します。
    ///
    /// 責務: 端と継ぎ目を丸めた線にし、破線の時だけ `RouteMapMetrics.dashPattern` を使います。
    /// - Parameters:
    ///   - width: 線の太さ(pt)。
    ///   - isDashed: 破線で描くか。
    /// - Returns: 線の描き方。
    private static func strokeStyle(width: CGFloat, isDashed: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: isDashed ? RouteMapMetrics.dashPattern : [])
    }

    /// 表示範囲からカメラの位置を作ります。
    ///
    /// 責務: 範囲があれば `RouteMapFraming` で表示範囲へ直し、無ければ自動にします。
    /// - Parameter bounds: 表示する範囲。
    /// - Returns: カメラの位置。
    private static func cameraPosition(for bounds: GeoBoundingBox?) -> MapCameraPosition {
        guard let bounds else { return .automatic }
        return .rect(RouteMapFraming().mapRect(for: bounds))
    }

    /// 座標の列を MapKit の座標の列へ直します。
    ///
    /// 責務: 順序を保って1点ずつ変換します。
    /// - Parameter coordinates: 座標の列。
    /// - Returns: MapKit の座標の列。
    private static func mapCoordinates(_ coordinates: [GeoCoordinate]) -> [CLLocationCoordinate2D] {
        coordinates.map(mapCoordinate)
    }

    /// 座標を MapKit の座標へ直します。
    ///
    /// 責務: 緯度・経度をそのまま `CLLocationCoordinate2D` へ詰めます。
    /// - Parameter coordinate: 座標。
    /// - Returns: MapKit の座標。
    private static func mapCoordinate(_ coordinate: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
