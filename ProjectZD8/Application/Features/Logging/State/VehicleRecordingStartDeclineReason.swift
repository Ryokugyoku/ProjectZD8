/// 常駐リンク監視からの記録開始要求を、調停役が開始せずに断った理由です。
nonisolated enum VehicleRecordingStartDeclineReason: Equatable, Sendable {
    /// 依頼済みの記録の照合中・記録中に新しい開始要求が届きました(想定外の重複要求)。
    case coordinatorBusy(VehicleRecordingCoordinatorPhase)
    /// 手動接続などの別の接続セッションが進行中でした。
    case anotherSessionActive
}
