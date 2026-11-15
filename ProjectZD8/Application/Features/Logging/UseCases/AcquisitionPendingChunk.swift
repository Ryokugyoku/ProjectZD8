import Foundation

/// 保存待ちバッファから組み立てた、commit前のチャンクと失われた場合の区間情報です。
nonisolated struct AcquisitionPendingChunk: Equatable, Sendable {
    /// commitするチャンクです。
    let chunk: ConnectionSessionAcquisitionChunk
    /// バッファ先頭から取り出した終端済みbatchの件数です。
    let batchCount: Int
    /// commitに成功した後に次へ割り当てる記録順序です。
    let nextSequenceAfterCommit: Int64
    /// チャンクが表す区間の最初の実時刻です。
    let firstObservedAt: Date
    /// チャンクが表す区間の最後の実時刻です。
    let lastObservedAt: Date
    /// チャンクの最初のRawが属する区間番号です。Rawが無い場合は `nil` です。
    let firstSegmentOrdinal: Int?
    /// チャンクの最後のRawが属する区間番号です。Rawが無い場合は `nil` です。
    let lastSegmentOrdinal: Int?

    /// commit前のチャンクと区間情報を固定します。
    ///
    /// 責務: 1件のチャンクと、成功時・失敗時にバッファと欠損記録が使う値をまとめます。
    /// - Parameters:
    ///   - chunk: commitするチャンク。
    ///   - batchCount: バッファ先頭から取り出した終端済みbatchの件数。
    ///   - nextSequenceAfterCommit: commit成功後に次へ割り当てる記録順序。
    ///   - firstObservedAt: チャンクが表す区間の最初の実時刻。
    ///   - lastObservedAt: チャンクが表す区間の最後の実時刻。
    ///   - firstSegmentOrdinal: 最初のRawが属する区間番号。
    ///   - lastSegmentOrdinal: 最後のRawが属する区間番号。
    init(
        chunk: ConnectionSessionAcquisitionChunk,
        batchCount: Int,
        nextSequenceAfterCommit: Int64,
        firstObservedAt: Date,
        lastObservedAt: Date,
        firstSegmentOrdinal: Int?,
        lastSegmentOrdinal: Int?
    ) {
        self.chunk = chunk
        self.batchCount = batchCount
        self.nextSequenceAfterCommit = nextSequenceAfterCommit
        self.firstObservedAt = firstObservedAt
        self.lastObservedAt = lastObservedAt
        self.firstSegmentOrdinal = firstSegmentOrdinal
        self.lastSegmentOrdinal = lastSegmentOrdinal
    }
}
