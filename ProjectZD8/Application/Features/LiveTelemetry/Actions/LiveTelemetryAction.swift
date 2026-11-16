/// リアルタイムPID取得をApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定OBD終端から、登録済み車両(車種適用済み)または未登録車両の継続取得開始を要求します。
    ///
    /// `adapterProbeEvidence` は常駐リンクの初期化時に判定したアダプター判定結果で、取得manifestへ記録します。判定していなければ `nil` です。
    case startRequested(
        OBDConnectionEndpoint,
        LiveTelemetryVehicleContext,
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence? = nil
    )
    /// 直近の接続終端で継続取得の再開を要求します。
    case retryRequested
    /// ユーザーの[切断]で現在の継続取得を終了します。終了理由は `userDisconnected` です。
    case stopRequested
    /// ユーザーの[切断]以外の理由(サインアウト・接続の置き換え・接続対象の喪失)で現在の継続取得を終了します。
    ///
    /// 取得記録と接続セッションの終了理由は、指定した理由になります。
    case endRequested(ConnectionSessionEndReason)
    /// アプリがバックグラウンドへ移行したことを通知し、保存待ちの取得記録を保存させます。
    case backgroundTransitionOccurred
    /// アプリがフォアグラウンドへ戻ったことを通知し、一時停止中なら復帰を試させます。
    case foregroundTransitionOccurred
    /// アダプターとのリンクが送受信可能(`true`)または切断(`false`)になったことを通知します。
    case adapterLinkAvailabilityChanged(isAvailable: Bool)
}
