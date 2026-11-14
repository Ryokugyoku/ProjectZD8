import Foundation

/// 受信した応答と取得証跡をメモリ上に積み、終端済みbatch単位でチャンクへ組み立てます。
///
/// 記録順序はチャンクを組み立てる時に受信順で割り当てます。commitに失敗したチャンクの番号は
/// 次のチャンクで再利用するため、保存済みRawの記録順序は欠番・重複なく増えます。
/// 未完了のbatchとその応答はチャンクへ入れず、終端状態になるまでバッファに残します。
nonisolated struct AcquisitionChunkBuffer: Equatable, Sendable {
    /// 次に割り当てる記録順序です。
    private(set) var nextSequence: Int64
    /// 周回順に並ぶ保存待ちbatchです。未完了のbatchは末尾の1件だけです。
    private(set) var batches: [AcquisitionBufferedBatch] = []

    /// 空のバッファを生成します。
    ///
    /// 責務: セッション内で次に割り当てる記録順序を固定します。
    /// - Parameter nextSequence: 保存済みRawの続きから割り当てる記録順序。
    init(nextSequence: Int64) {
        self.nextSequence = nextSequence
    }

    /// バッファ内のRaw件数を返します。
    ///
    /// 責務: commit判定に使う保存待ちRaw件数を数えます。
    var bufferedRawCount: Int { batches.reduce(0) { $0 + $1.raws.count } }

    /// 保存済みRawの最後の記録順序を返します。
    ///
    /// 責務: 区間を閉じる時の最終記録順序を返します。1件も保存していない場合は `nil`。
    var lastCommittedSequence: Int64? { nextSequence > 0 ? nextSequence - 1 : nil }

    /// 未完了のbatchを返します。
    ///
    /// 責務: 結果を受け付け中の周回を返します。無い場合は `nil`。
    var openBatch: AcquisitionBufferedBatch? { batches.last.flatMap { $0.isTerminal ? nil : $0 } }

    /// 周回開始時の未完了batchを積みます。
    ///
    /// 責務: 前の周回が終端済みであることを確かめて新しい周回を末尾へ追加します。
    /// - Parameter batch: 周回開始時の未完了batch。
    /// - Throws: 未完了のbatchが残っている場合は `.invalidInput`。
    mutating func begin(_ batch: AcquisitionBufferedBatch) throws {
        guard openBatch == nil else { throw LiveTelemetryAcquisitionRecordingError.invalidInput }
        batches.append(batch)
    }

    /// 未完了のbatchを書き換えます。
    ///
    /// 責務: 末尾の未完了batchだけへ変更を適用します。
    /// - Parameters:
    ///   - batchOrdinal: 変更対象のbatch番号。
    ///   - change: 未完了batchへ適用する変更。
    /// - Throws: 該当する未完了batchが無い場合は `.invalidInput`、または `change` が送出したエラー。
    mutating func updateOpenBatch(
        ordinal batchOrdinal: Int64,
        _ change: (inout AcquisitionBufferedBatch) throws -> Void
    ) throws {
        guard let index = batches.indices.last, !batches[index].isTerminal,
              batches[index].identity.ordinal == batchOrdinal else {
            throw LiveTelemetryAcquisitionRecordingError.invalidInput
        }
        try change(&batches[index])
    }

    /// 未完了のbatchがあれば打ち切ります。
    ///
    /// 責務: 取得終了時に末尾の未完了batchを終端状態へ遷移させます。
    /// - Parameters:
    ///   - completedAt: 打ち切りを確定した実時間。
    ///   - classifier: request結果列をbatch失敗理由へ集約する分類器。
    mutating func abandonOpenBatch(at completedAt: Date, classifier: AcquisitionTransportOutcomeClassifier) {
        guard let index = batches.indices.last else { return }
        batches[index].abandon(at: completedAt, classifier: classifier)
    }

    /// 終端済みbatchをチャンクへ組み立てます。
    ///
    /// 責務: 先頭から連続する終端済みbatchへ記録順序を割り当て、commit前のチャンクへ変換します。
    /// - Parameter sessionID: チャンクを所有する接続セッション。
    /// - Returns: commit前のチャンク。終端済みbatchが無い場合は `nil`。
    /// - Throws: Domain不変条件に違反する場合のエラー。
    func pendingChunk(sessionID: ConnectionSessionID) throws -> AcquisitionPendingChunk? {
        let terminal = batches.prefix { $0.isTerminal }
        guard !terminal.isEmpty else { return nil }
        var sequence = nextSequence
        var rawEntries: [ConnectionSessionRawLogEntry] = []
        var evidences: [AcquisitionBatchEvidence] = []
        for batch in terminal {
            let built = try batch.evidence(firstSequence: sequence)
            sequence += Int64(built.rawEntries.count)
            rawEntries += built.rawEntries
            evidences.append(built.batch)
        }
        let times = terminal.flatMap { [$0.startedAt] + $0.raws.map(\.observedAt) + [$0.completedAt].compactMap { $0 } }
        let raws = terminal.flatMap(\.raws)
        return AcquisitionPendingChunk(
            chunk: ConnectionSessionAcquisitionChunk(sessionID: sessionID, rawEntries: rawEntries, batches: evidences),
            batchCount: terminal.count,
            nextSequenceAfterCommit: sequence,
            firstObservedAt: times.min() ?? terminal[terminal.startIndex].startedAt,
            lastObservedAt: times.max() ?? terminal[terminal.startIndex].startedAt,
            firstSegmentOrdinal: raws.first?.segmentOrdinal,
            lastSegmentOrdinal: raws.last?.segmentOrdinal
        )
    }

    /// commitに成功したチャンクの分をバッファから取り除きます。
    ///
    /// 責務: 保存済みbatchを取り除き、割り当てた記録順序を確定します。
    /// - Parameter pending: commitに成功したチャンク。
    mutating func removeCommitted(_ pending: AcquisitionPendingChunk) {
        batches.removeFirst(min(pending.batchCount, batches.count))
        nextSequence = pending.nextSequenceAfterCommit
    }

    /// commitに失敗したチャンクの分をバッファから破棄します。
    ///
    /// 責務: 保存できなかったbatchを再送せずに取り除き、記録順序は次のチャンクで再利用させます。
    /// - Parameter pending: commitに失敗したチャンク。
    mutating func removeDiscarded(_ pending: AcquisitionPendingChunk) {
        batches.removeFirst(min(pending.batchCount, batches.count))
    }
}
