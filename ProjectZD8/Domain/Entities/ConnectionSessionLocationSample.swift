/// 接続セッションに保存された1点の位置です。
nonisolated struct ConnectionSessionLocationSample: Equatable, Sendable {
    /// セッション内の連番(昇順)。
    let sequence: Int64
    /// 観測された位置。
    let fix: LocationFix
}
