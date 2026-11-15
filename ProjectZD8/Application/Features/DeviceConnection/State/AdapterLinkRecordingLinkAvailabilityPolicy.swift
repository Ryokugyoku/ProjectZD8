/// 記録中の常駐リンクの状態変化から、記録側へ伝えるリンク可用性の変化を決める純粋な方針です。
///
/// 記録中にリンクを失っても監視は停止を要求せず、取得側の途切れ処理に任せます。取得側が復帰の機会を逃さないよう、
/// `ready` への出入りだけを可用性の変化として伝えます。
nonisolated struct AdapterLinkRecordingLinkAvailabilityPolicy: Sendable {
    /// 状態を持たない方針を生成します。
    ///
    /// 責務: 可用性の判定を構築します。
    init() {}

    /// 1件のイベントで記録側へ伝える可用性の変化を返します。
    ///
    /// 責務: 記録中かつリンク開始済みで、リンク状態が `ready` 以外から `ready` へ変わったら復帰、
    /// `ready` から `ready` 以外へ変わったら断を返します。
    /// - Parameters:
    ///   - event: 入力されたイベント。
    ///   - state: イベントを処理する直前の監視状態。
    ///   - conditions: 直前のリンク状態とリンクの接続対象を含む条件。
    /// - Returns: 復帰なら `true`、断なら `false`。伝える変化が無ければ `nil`。
    func availabilityChange(
        on event: AdapterLinkSupervisionEvent,
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> Bool? {
        guard case .recording = state,
              conditions.linkPreference != nil,
              case let .linkStateChanged(linkState) = event else { return nil }
        let wasReady = conditions.linkState == .ready
        let isReady = linkState == .ready
        guard wasReady != isReady else { return nil }
        return isReady
    }
}
