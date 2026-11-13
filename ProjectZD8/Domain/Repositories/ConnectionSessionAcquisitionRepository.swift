import Foundation

/// sessionのimmutable manifestとappend-only Raw境界を整合して保存する能力です。
nonisolated protocol ConnectionSessionAcquisitionRepository: Sendable {
    /// 未登録sessionへmanifestとRaw開始境界を1回の原子操作で保存します。
    ///
    /// 責務: immutable manifestと最初のRaw要求前の開始境界を部分成功なしで新規関連付けします。
    /// - Parameters:
    ///   - manifest: 保存後に更新しない取得manifest。
    ///   - startedAt: 最初のRaw要求を許可する直前の開始境界時刻。
    ///   - sessionID: semantic identityへ含めず両証拠の所有関係だけを結ぶsession識別子。
    /// - Throws: 同じ組の重複、異なる組との競合、または保存先失敗を区別する `ConnectionSessionAcquisitionRepositoryError`。
    func saveStartOnce(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        for sessionID: ConnectionSessionID
    ) throws

    /// 開始済みsessionへRaw終了境界を追記します。
    ///
    /// 責務: 保存済みmanifestや開始境界を更新せず1件の終了境界だけを追記します。
    /// - Parameters:
    ///   - endedAt: Raw取得が停止した境界時刻。
    ///   - reason: Raw取得が停止した直接原因。
    ///   - sessionID: 終了境界を所有するsession識別子。
    /// - Throws: 重複、競合、開始欠落、時系列違反、または保存先失敗を区別する `ConnectionSessionAcquisitionRepositoryError`。
    func appendEnd(
        at endedAt: Date,
        reason: ConnectionSessionEndReason,
        for sessionID: ConnectionSessionID
    ) throws

    /// sessionに関連付けられた取得manifestを読み取ります。
    ///
    /// 責務: sessionに原子的に保存されたimmutable manifestを変更せず返します。
    /// - Parameter sessionID: 読取対象のsession識別子。
    /// - Returns: 保存済みのimmutable取得manifest。
    /// - Throws: 未登録または読取先失敗を区別する `ConnectionSessionAcquisitionRepositoryError`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest

    /// sessionへ保存済みのRaw取得境界を追記順で読み取ります。
    ///
    /// 責務: 原子的に保存された開始と後から追記された終了を変更せず返します。
    /// - Parameter sessionID: 読取対象のsession識別子。
    /// - Returns: 開始から終了の順に並ぶ保存済み境界event。
    /// - Throws: 読取先を利用できない場合は `ConnectionSessionAcquisitionRepositoryError.unavailable`。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence]
}
