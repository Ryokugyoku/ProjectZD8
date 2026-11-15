/// 常駐リンク監視から記録の開始・停止を記録側へ依頼する狭い境界です。
///
/// 具象の Logging/LiveTelemetry 型には依存しません。VINから登録済み車両を引く処理は実装側の責務です。
@MainActor
protocol AdapterLinkRecordingControlPort: AnyObject {
    /// 記録の開始を要求します。
    ///
    /// 責務: 1件の記録開始要求を記録側へ渡します。記録の終了は `AdapterLinkSupervisionUseCase.recordingDidFinish(endReason:)` で返します。
    /// - Parameter request: 接続終端・読み取ったVIN・アダプター判定結果。
    func requestRecordingStart(_ request: AdapterLinkRecordingStartRequest)

    /// 進行中の記録の停止を要求します。
    ///
    /// 責務: リンク断や稼働条件の喪失で記録を続けられないことを記録側へ伝えます。
    /// 停止の完了は `AdapterLinkSupervisionUseCase.recordingDidFinish(endReason:)` で返します。
    func requestRecordingStop()
}
