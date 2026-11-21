#if os(macOS)
/// 解析の走行ルートの端の印を、macOS の地図部品が描く印の契約へ対応づけます(座標と始点・終点をそのまま使います)。
extension RouteAnalysisMapMarker: RouteMapMarkerContent {}
#endif
