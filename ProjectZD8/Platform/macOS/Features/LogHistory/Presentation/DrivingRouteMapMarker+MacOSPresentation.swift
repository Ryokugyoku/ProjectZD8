#if os(macOS)
/// 走行ルートの端の印を、Shared の地図部品の印の契約へ接続します。
///
/// プロパティ名が汎用契約と一致するため、準拠宣言だけで描画できます。
extension DrivingRouteMapMarker: RouteMapMarkerContent {}
#endif
