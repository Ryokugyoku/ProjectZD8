/// 位置記録の判定結果です。
nonisolated struct SessionLocationRecordingDecision: Equatable, Sendable {
    /// 位置を取得する場合は `true`。
    let acquiresLocation: Bool
    /// 記録する状態の種類。
    let eventKind: ConnectionSessionLocationEventKind
}
