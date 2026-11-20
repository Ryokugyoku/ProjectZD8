/// 走行ルートの端の印の種類です。地図の印(Shared の地図部品を含む)が参照します。
nonisolated enum DrivingRouteEndpoint: Equatable, Sendable {
    /// ルートの始点。
    case start
    /// ルートの終点。
    case end
}
