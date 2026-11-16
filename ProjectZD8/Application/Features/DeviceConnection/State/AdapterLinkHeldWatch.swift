import Foundation

/// ユーザー切断後の抑止中に、ECU がまだ応答しているか(同じ走行が続いているか)を見張る進行状況です。
nonisolated struct AdapterLinkHeldWatch: Equatable, Sendable {
    /// 抑止に入った直後の値です。見張りは記録の終了通知を受けた後に始めます。
    static let awaitingStart = AdapterLinkHeldWatch(consecutiveNoResponses: 0, phase: .awaitingStart)

    /// 連続して受け取った ECU の無応答の回数です。応答を受け取ると0へ戻ります。
    let consecutiveNoResponses: Int

    /// 見張りの段階です。
    let phase: AdapterLinkHeldWatchPhase

    /// 見張りの進行状況を固定して生成します。
    ///
    /// 責務: 連続無応答の回数と段階を1件の不変値へまとめます。
    /// - Parameters:
    ///   - consecutiveNoResponses: 連続した無応答の回数。
    ///   - phase: 見張りの段階。
    init(consecutiveNoResponses: Int, phase: AdapterLinkHeldWatchPhase) {
        self.consecutiveNoResponses = consecutiveNoResponses
        self.phase = phase
    }
}
