/// 記録中の常時表示の[切断]操作を、手動切断と同じ取得停止の要求へ変換します。
///
/// 記録中でなければ何もしません(停止済み・停止処理中・未開始のいずれでも成功扱いで終わります)。
@MainActor
final class StopRecordingFromSessionActivityUseCase {
    /// PID継続取得の現在状態を返す処理です。
    private let telemetryState: @MainActor () -> LiveTelemetryState
    /// 手動切断と同じ経路で取得停止を要求する処理です。
    private let requestStop: @MainActor () -> Void
    /// 停止要求を受け付けたか断ったかを残す診断記録です。未設定なら記録しません。
    private let lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)?

    /// 状態の取得元と停止要求先を固定して生成します。
    ///
    /// 責務: 停止の判定に使う状態と停止の送り先を注入で受け取ります。
    /// - Parameters:
    ///   - telemetryState: PID継続取得の現在状態を返す処理。
    ///   - requestStop: 手動切断と同じ経路(`LiveTelemetryAction.stopRequested`)で停止を要求する処理。
    ///   - lifecycleDiagnostics: 停止要求を受け付けたか断ったかを残す診断記録。
    init(
        telemetryState: @escaping @MainActor () -> LiveTelemetryState,
        requestStop: @escaping @MainActor () -> Void,
        lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)? = nil
    ) {
        self.telemetryState = telemetryState
        self.requestStop = requestStop
        self.lifecycleDiagnostics = lifecycleDiagnostics
    }

    /// [切断]操作を実行します。
    ///
    /// 責務: 記録中(停止処理中を除く)の時だけ停止を要求し、受け付けたか断ったかを診断へ残します。
    /// - Returns: 停止を要求したなら `true`、記録中でなく何もしなかったなら `false`。
    @discardableResult
    func execute() -> Bool {
        let state = telemetryState()
        guard state.isConnectionActive, !state.isDisconnecting else {
            lifecycleDiagnostics?.stopRequestDeclined()
            return false
        }
        requestStop()
        lifecycleDiagnostics?.stopRequestAccepted()
        return true
    }
}
