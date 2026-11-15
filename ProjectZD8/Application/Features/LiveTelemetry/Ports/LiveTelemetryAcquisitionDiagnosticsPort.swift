/// 応答駆動の取得ループの開始・段階の変化・終了を診断記録へ残すための狭い境界です。
///
/// 受け取る値は列挙値と試行番号だけです。VIN・アカウント識別子・セッションID・終端の識別子・PIDの値・Rawの中身は渡しません。
/// 状態の観測は `LiveTelemetryState` で行えます。この境界はログ等への出力だけを担います。
@MainActor
protocol LiveTelemetryAcquisitionDiagnosticsPort: AnyObject {
    /// 取得ループを始めたことを記録します。
    ///
    /// 責務: 1件の取得開始を診断記録へ渡します。
    func acquisitionStarted()

    /// 取得ループの段階が変わったことを記録します。
    ///
    /// 責務: 1件の段階の変化(原因・回復段階・試行番号を含む)を診断記録へ渡します。
    /// - Parameter phase: 変化後の段階。
    func acquisitionPhaseChanged(_ phase: LiveTelemetryAcquisitionPhase)

    /// 停止の指示、または新しい取得への切替で取得ループが終わったことを記録します。
    ///
    /// 責務: 1件の停止による終了を診断記録へ渡します。
    func acquisitionStopped()

    /// 回復段階を使い切った後の猶予内に復帰せず、取得ループが終わったことを記録します。
    ///
    /// 責務: 1件の猶予切れによる終了とその原因を診断記録へ渡します。
    /// - Parameter cause: 取得が途切れた原因。
    func acquisitionGracePeriodExpired(cause: LiveTelemetryInterruptionCause)

    /// 取得記録の開始・保存に失敗し、取得ループが終わったことを記録します。
    ///
    /// 責務: 1件の記録失敗による終了を診断記録へ渡します。
    func acquisitionRecordingFailed()
}
