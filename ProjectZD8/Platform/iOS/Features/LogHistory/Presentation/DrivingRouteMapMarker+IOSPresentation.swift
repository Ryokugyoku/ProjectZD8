#if os(iOS)
/// 走行ルートの端の印を、iPhone の地図部品が描く印の契約へ対応づけます(座標と始点・終点をそのまま使います)。
extension DrivingRouteMapMarker: RouteMapMarkerContent {}
#endif
