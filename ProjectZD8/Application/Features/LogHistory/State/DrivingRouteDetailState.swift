/// セッション詳細の走行ルートを画面へ公開する状態です。
nonisolated struct DrivingRouteDetailState: Equatable, Sendable {
    /// 表示中のセッションの ID です。表示していない時は `nil` です。
    var sessionID: ConnectionSessionID?
    /// 読み込みの段階です。
    var phase: DrivingRouteDetailPhase
}
