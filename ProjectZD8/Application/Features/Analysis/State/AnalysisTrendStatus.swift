/// 長期傾向データの準備状況です。
nonisolated enum AnalysisTrendStatus: Equatable, Sendable {
    /// 未要求。
    case idle
    /// 集計中。
    case building
    /// 指定車両の長期傾向を取得できる。
    case ready(VehicleID)
}
