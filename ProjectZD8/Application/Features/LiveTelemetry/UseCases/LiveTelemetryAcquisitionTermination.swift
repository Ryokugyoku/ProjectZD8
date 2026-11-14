/// 応答駆動の取得ループが終わった理由です。
nonisolated enum LiveTelemetryAcquisitionTermination: Equatable, Sendable {
    /// 停止の指示、または新しい取得への切替で終わりました。
    case stopped
    /// 1周回まるごと車両の応答がありませんでした。
    case noVehicleResponse
    /// アダプターまたは車両との通信境界を失いました。
    case connectionLost
    /// 取得記録の開始・保存に失敗し、取得を続けられません。
    case recordingFailed

    /// 取得記録へ渡す終了原因を返します。
    ///
    /// 責務: ループの終了理由を接続セッションの終了原因へ変換します。
    var sessionEndReason: ConnectionSessionEndReason {
        switch self {
        case .stopped: .userDisconnected
        case .noVehicleResponse: .vehicleNoResponse
        case .connectionLost: .connectionLost
        case .recordingFailed: .acquisitionFailed
        }
    }
}
