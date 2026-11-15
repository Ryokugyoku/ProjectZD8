/// 手動接続がアダプターを使っている段階です。常駐リンク監視の抑止の開始・解除を1回ずつ伝えるために使います。
nonisolated enum VehicleRecordingManualAdapterUse: Equatable, Sendable {
    /// 手動接続はアダプターを使っていません。
    case idle
    /// 手動接続の車両識別がアダプターへ接続しています。
    case identifying
    /// 手動接続で始めた記録のテレメトリがアダプターを使っています。
    case recording
}
