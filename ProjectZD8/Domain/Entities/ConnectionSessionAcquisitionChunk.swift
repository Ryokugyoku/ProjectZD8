import Foundation

/// 1回の書き込みトランザクションで保存する、取得済みRawと取得証跡のまとまりです。
///
/// Raw の `sequence` は呼び出し側が採番済みの値を持ちます。チャンクに含める Raw は
/// `monotonicNanoseconds` と `segmentOrdinal` を必ず持ち、batch は終端状態まで確定した値です。
/// 内容の整合性は保存時に `ConnectionSessionAcquisitionChunkRepository.commit(_:)` が検証します。
nonisolated struct ConnectionSessionAcquisitionChunk: Equatable, Sendable {
    /// Rawと取得証跡を所有する接続セッションです。
    let sessionID: ConnectionSessionID
    /// 採番済みの未デコード応答です。保存順に並びます。
    let rawEntries: [ConnectionSessionRawLogEntry]
    /// 同じチャンクに属する、終端状態まで確定した取得batchとそのrequest結果です。
    let batches: [AcquisitionBatchEvidence]

    /// 保存対象のRawと取得証跡を1件のチャンクへまとめます。
    ///
    /// 責務: 呼び出し側が確定した値を変更せずに保持します。
    /// - Parameters:
    ///   - sessionID: Rawと取得証跡を所有する接続セッション。
    ///   - rawEntries: 採番済みの未デコード応答。
    ///   - batches: 終端状態まで確定した取得batch。
    init(
        sessionID: ConnectionSessionID,
        rawEntries: [ConnectionSessionRawLogEntry],
        batches: [AcquisitionBatchEvidence]
    ) {
        self.sessionID = sessionID
        self.rawEntries = rawEntries
        self.batches = batches
    }

    /// Rawも取得証跡も含まないかを返します。
    ///
    /// 責務: 保存処理を省略してよい空チャンクかを判定します。
    var isEmpty: Bool {
        rawEntries.isEmpty && batches.isEmpty
    }
}
