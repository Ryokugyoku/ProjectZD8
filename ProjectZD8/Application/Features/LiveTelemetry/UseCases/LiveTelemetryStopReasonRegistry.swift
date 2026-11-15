import Synchronization

/// 取得ループの世代ごとに、停止を指示した理由を覚えておく入れ物です。
///
/// 取得Taskの取り消しより先に、同期的に理由を結び付けられるようにするための型です。取り消しの経路(ストリームの購読終了・
/// `stop(reason:)`・新しい世代の `start`)に関係なく、記録を終える時点で理由を引けます。最初に結び付けた理由を優先します。
nonisolated final class LiveTelemetryStopReasonRegistry: Sendable {
    /// 世代ごとの停止理由です。
    private let reasons = Mutex<[UInt: ConnectionSessionEndReason]>([:])

    /// 空の入れ物を生成します。
    ///
    /// 責務: どの世代にも理由を持たない初期状態を構築します。
    init() {}

    /// 世代へ停止の理由を結び付けます。
    ///
    /// 責務: 既に理由がある世代では先の理由を残し、無い世代にだけ理由を記録します。
    /// - Parameters:
    ///   - reason: 停止の理由。
    ///   - generation: 止める世代。
    func register(_ reason: ConnectionSessionEndReason, for generation: UInt) {
        reasons.withLock { current in
            if current[generation] == nil { current[generation] = reason }
        }
    }

    /// 世代の停止理由を取り出し、記録から消します。
    ///
    /// 責務: 記録を終える時点で1回だけ理由を返し、以後の同じ世代の問い合わせでは `nil` を返します。
    /// - Parameter generation: 終える世代。
    /// - Returns: 結び付けた理由。無ければ `nil`。
    func take(for generation: UInt) -> ConnectionSessionEndReason? {
        reasons.withLock { current in current.removeValue(forKey: generation) }
    }
}
