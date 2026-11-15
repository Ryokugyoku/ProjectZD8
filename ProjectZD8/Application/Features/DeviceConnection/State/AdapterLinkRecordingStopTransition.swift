/// 稼働条件の喪失・接続の置き換え・監視の停止で、常駐リンク上の監視と記録を終わらせる純粋な遷移です。
///
/// リンク断は扱いません(記録を止めずに取得側の猶予に任せるため、`AdapterLinkLifecycleTransition.linkLost(from:)` が扱います)。
nonisolated struct AdapterLinkRecordingStopTransition: Sendable {
    /// 記録を続けられなくなった時の巻き戻し先と作用を返します。
    ///
    /// 責務: 進行中の処理の取り消しと通知の取り下げを行い、記録中なら理由を付けて停止を要求して終了へ、
    /// 終了中は終了のまま、それ以外(抑止中を含む)は待機へ戻します。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - reason: 記録中だった場合に記録側へ渡す停止理由。
    /// - Returns: 記録中・終了中なら `finishing`、それ以外は `standby` への遷移。
    func stopped(
        from state: AdapterLinkSupervisionState,
        reason: AdapterLinkRecordingStopReason
    ) -> AdapterLinkSupervisionTransitionResult {
        switch state {
        case .recording:
            AdapterLinkSupervisionTransitionResult(
                state: .finishing,
                effects: [.cancelOperations, .dismissNotification, .requestRecordingStop(reason)]
            )
        case .finishing:
            AdapterLinkSupervisionTransitionResult(state: .finishing, effects: [.cancelOperations, .dismissNotification])
        case .standby, .initializing, .confirmingVehicle, .vehicleDetected, .heldAfterUserStop:
            AdapterLinkSupervisionTransitionResult(state: .standby, effects: [.cancelOperations, .dismissNotification])
        }
    }
}
