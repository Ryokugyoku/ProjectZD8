/// 常駐リンク監視から記録の開始・停止とリンク可用性の変化を記録側へ伝える狭い境界です。
///
/// 具象の Logging/LiveTelemetry 型には依存しません。VINから登録済み車両を引く処理は実装側の責務です。
@MainActor
protocol AdapterLinkRecordingControlPort: AnyObject {
    /// 記録の開始を要求します。
    ///
    /// 責務: 1件の記録開始要求を記録側へ渡します。記録の終了は `AdapterLinkSupervisionUseCase.recordingDidFinish(endReason:)` で返します。
    /// - Parameter request: 接続終端・読み取ったVIN・アダプター判定結果。
    func requestRecordingStart(_ request: AdapterLinkRecordingStartRequest)

    /// 進行中の記録の停止を、理由を付けて要求します。
    ///
    /// 責務: 稼働条件の喪失・接続の置き換え・監視の停止で記録を続けられないことを、保存すべき終了理由とともに記録側へ伝えます。
    /// リンク断では呼びません。停止の完了は `AdapterLinkSupervisionUseCase.recordingDidFinish(endReason:)` で返します。
    /// - Parameter reason: 停止の理由。ユーザーの[切断]は含みません。
    func requestRecordingStop(reason: AdapterLinkRecordingStopReason)

    /// 記録中の常駐リンクが送受信できる状態へ戻った・切れたことを伝えます。
    ///
    /// 責務: 記録中のリンク可用性の変化を、取得側の復帰の機会として記録側へ渡します。記録を止める指示ではありません。
    /// - Parameter isAvailable: リンクが `ready` へ戻ったら `true`、`ready` でなくなったら `false`。
    func recordingLinkAvailabilityDidChange(isAvailable: Bool)
}
