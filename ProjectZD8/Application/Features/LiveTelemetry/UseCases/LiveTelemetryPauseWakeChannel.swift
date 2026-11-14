import Synchronization

/// 一時停止中の取得Taskへ、外から届いた起床の理由を渡す通り道です。
///
/// 一時停止の間だけ開き、閉じている間に届いた理由は捨てます。取得ループの actor が所有し、
/// 外部からの通知と猶予の期限待ちの両方がここへ理由を送ります。
nonisolated final class LiveTelemetryPauseWakeChannel: Sendable {
    /// 開いている間の送出口です。
    private let continuation = Mutex<AsyncStream<LiveTelemetryPauseWakeReason>.Continuation?>(nil)

    /// 閉じた状態の通り道を生成します。
    ///
    /// 責務: 起床理由の送出口を持たない初期状態を構築します。
    init() {}

    /// 通り道を開き、起床理由のストリームを返します。
    ///
    /// 責務: 前に開いていたストリームを閉じてから、新しいストリームを開きます。
    /// - Returns: 開いている間に届いた起床理由を届いた順に流すストリーム。
    func open() -> AsyncStream<LiveTelemetryPauseWakeReason> {
        let (stream, newContinuation) = AsyncStream.makeStream(
            of: LiveTelemetryPauseWakeReason.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        let previous = continuation.withLock { current in
            defer { current = newContinuation }
            return current
        }
        previous?.finish()
        return stream
    }

    /// 起床理由を送ります。
    ///
    /// 責務: 開いていれば理由を流し、閉じていれば捨てます。
    /// - Parameter reason: 起床の理由。
    func send(_ reason: LiveTelemetryPauseWakeReason) {
        let current = continuation.withLock { $0 }
        current?.yield(reason)
    }

    /// 通り道を閉じます。
    ///
    /// 責務: 開いているストリームを終え、以後の理由を捨てる状態へ戻します。
    func close() {
        let previous = continuation.withLock { current in
            defer { current = nil }
            return current
        }
        previous?.finish()
    }
}
