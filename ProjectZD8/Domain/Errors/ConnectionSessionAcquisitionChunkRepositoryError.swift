/// 取得チャンク保存の排他的な失敗理由です。
nonisolated enum ConnectionSessionAcquisitionChunkRepositoryError: Error, Equatable, Sendable {
    /// チャンクを所有する接続セッションが保存されていません。
    case sessionNotFound
    /// チャンクを所有する接続セッションは終了済みです。
    case sessionEnded
    /// チャンク内に同じRaw `sequence` が複数あります。
    case duplicateSequenceInChunk
    /// チャンクのRaw `sequence` がセッションの保存済み行と重複しています。
    case sequenceAlreadyStored
    /// チャンクのRawが単調時計ナノ秒またはセグメント番号を持っていません。
    case rawTimingMissing
    /// チャンクのRawが、開始を保存していないセグメントを指しています。
    case segmentNotStarted
    /// チャンクに取得batchがあるのに、セッションの取得manifestが確定していません。
    case acquisitionStartMissing
    /// チャンクの取得batchが終端状態まで確定していません。
    case batchNotTerminal
    /// チャンク内に同じbatch番号が複数あります。
    case duplicateBatchInChunk
    /// チャンクのbatch番号がセッションの保存済みbatchと重複しています。
    case batchAlreadyStored
    /// respondedのrequestが、チャンクにも保存済み行にもないRaw `sequence` を参照しています。
    case rawReferenceMissing
    /// 値の範囲外やDB制約違反など、上記以外の整合性違反です。
    case integrityConflict
    /// 保存先を利用できません。
    case unavailable
}
