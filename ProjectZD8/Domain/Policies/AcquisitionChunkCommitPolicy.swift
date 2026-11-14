/// 取得中の保存待ちバッファをチャンクとしてcommitする時機を判定します。
nonisolated struct AcquisitionChunkCommitPolicy: Sendable {
    /// この件数以上たまったらcommitするバッファ件数の上限です。
    static let bufferedCountLimit = 100
    /// 前回commitからこのナノ秒以上経過したらcommitする経過の上限です(1秒)。
    static let elapsedLimitNanoseconds: UInt64 = 1_000_000_000

    /// 状態を持たないチャンクcommit判定を生成します。
    ///
    /// 責務: 定数だけで判定するチャンクcommit Policyを構築します。
    init() {}

    /// バッファ件数と前回commitからの経過でcommitすべきかを返します。
    ///
    /// 責務: 空バッファは常に保留し、件数上限以上または経過上限以上ならcommitを指示します。
    /// - Parameters:
    ///   - bufferedCount: 保存待ちバッファの件数。
    ///   - elapsedSinceLastCommitNanoseconds: 前回commitからの単調時計上の経過ナノ秒。
    /// - Returns: commitすべきなら `true`。バッファが0件以下なら経過にかかわらず `false`。
    func shouldCommit(bufferedCount: Int, elapsedSinceLastCommitNanoseconds: UInt64) -> Bool {
        guard bufferedCount > 0 else { return false }
        return bufferedCount >= Self.bufferedCountLimit
            || elapsedSinceLastCommitNanoseconds >= Self.elapsedLimitNanoseconds
    }
}
