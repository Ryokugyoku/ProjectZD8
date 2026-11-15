/// 接続セッションを開始できなかった時にテレメトリを始めるかどうかの方針です。
nonisolated enum VehicleRecordingSessionRequirement: Equatable, Sendable {
    /// セッションがなくてもテレメトリを始めます。失敗はテレメトリ側の取得失敗として表示されます(手動接続の従来の挙動)。
    case optional
    /// セッションがなければテレメトリを始めず、開始失敗とします(常駐リンクからの記録)。
    case required
}
