/// 車両確認が低頻度の再確認を続けているか、休止しているかを表します。
nonisolated enum AdapterLinkVehicleConfirmationPhase: Equatable, Sendable {
    /// 確認窓の中で、車両確認の実行中または次の再確認までの待機中です。
    case probing

    /// 確認窓を使い切って再確認を止め、次の再接続かアプリ前面復帰を待っています。
    case paused
}
