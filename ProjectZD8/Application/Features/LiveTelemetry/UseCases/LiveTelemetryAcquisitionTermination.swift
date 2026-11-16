import Foundation

/// 応答駆動の取得ループが終わった理由です。
nonisolated enum LiveTelemetryAcquisitionTermination: Equatable, Sendable {
    /// 停止の指示、または新しい取得への切替で終わりました。終了原因は停止の理由で決まります(`sessionEndReason(stoppedFor:)`)。
    case stopped
    /// 取得が途切れ、回復段階を使い切った後の猶予内に復帰しませんでした。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - lastReceivedAt: 最後に正応答を受信した実時間。セッションの終了時刻に使います。
    case gracePeriodExpired(cause: LiveTelemetryInterruptionCause, lastReceivedAt: Date)
    /// 取得記録の開始・保存に失敗し、取得を続けられません。
    case recordingFailed

    /// ユーザーの[切断]で止めた場合に取得記録へ渡す終了原因を返します。
    ///
    /// 責務: 停止理由をユーザー切断として `sessionEndReason(stoppedFor:)` へ委ねます。
    var sessionEndReason: ConnectionSessionEndReason {
        sessionEndReason(stoppedFor: .userDisconnected)
    }

    /// 停止の指示に添えた理由を踏まえて、取得記録と終了通知へ渡す終了原因を返します。
    ///
    /// 責務: 停止は指示した理由へ、猶予切れは途切れの原因へ、記録失敗は取得失敗へ変換します。
    /// 取得記録(`recorder.finish`)と終了通知(`sessionDidEnd`)の両方がこの規則を使い、理由を一致させます。
    /// - Parameter stopReason: 停止を指示した理由。新しい取得への切替で止まった場合はユーザー切断。
    /// - Returns: 接続セッションの終了原因。
    func sessionEndReason(stoppedFor stopReason: ConnectionSessionEndReason) -> ConnectionSessionEndReason {
        switch self {
        case .stopped: stopReason
        case let .gracePeriodExpired(cause, _): cause.sessionEndReason
        case .recordingFailed: .acquisitionFailed
        }
    }

    /// セッションの終了時刻として使う実時間を返します。
    ///
    /// 責務: 猶予切れは最後に受信した時刻を返し、それ以外は終了を処理した時刻を使わせます。
    /// - Returns: 猶予切れなら最後に受信した実時間、それ以外は `nil`。
    var sessionEndedAt: Date? {
        if case let .gracePeriodExpired(_, lastReceivedAt) = self { return lastReceivedAt }
        return nil
    }
}
