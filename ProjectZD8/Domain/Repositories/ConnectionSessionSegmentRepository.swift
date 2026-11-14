import Foundation

/// 接続セッション内の連続取得区間を永続化する能力です。
nonisolated protocol ConnectionSessionSegmentRepository: Sendable {
    /// 未終了の連続取得区間を新規保存します。
    ///
    /// 責務: 1件の未終了区間を指定セッションへ追加します。
    /// - Parameters:
    ///   - segment: 終了情報を持たない開始時点の区間。
    ///   - sessionID: 区間を所有する接続セッション。
    /// - Throws: 終了情報を持つ区間は `ConnectionSessionRepositoryError.invalidState`、
    ///   番号重複・セッション不在・範囲外の値は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func beginSegment(_ segment: ConnectionSessionSegment, for sessionID: ConnectionSessionID) throws

    /// 未終了の連続取得区間へ終了情報を確定します。
    ///
    /// 責務: 1件の未終了区間を終了時刻、終了理由、最終記録順序を持つ終了済み状態へ遷移させます。
    /// - Parameters:
    ///   - segmentOrdinal: 終了する区間の番号。
    ///   - sessionID: 区間を所有する接続セッション。
    ///   - endedAt: 区間を終了した実時間。
    ///   - reason: 区間が終わった直接原因。
    ///   - lastSequence: 区間の最後の行の記録順序。行が1件もない場合は `nil`。
    /// - Throws: 区間不在または終了済みは `ConnectionSessionRepositoryError.invalidState`、
    ///   開始より前の終了時刻・`firstSequence` 未満の `lastSequence` は `.integrityConflict`、
    ///   それ以外の保存失敗は `.unavailable`。
    func finishSegment(
        ordinal segmentOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        reason: ConnectionSessionSegmentEndReason,
        lastSequence: Int64?
    ) throws

    /// セッションの連続取得区間を区間番号順で返します。
    ///
    /// 責務: 1件のセッションに保存された全区間を安定順で復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `segmentOrdinal` 昇順の区間。区間がないセッションでは空配列。
    /// - Throws: 保存値をDomainへ復元できない場合は `ConnectionSessionRepositoryError.integrityConflict`、
    ///   それ以外の読取失敗は `.unavailable`。
    func segments(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionSegment]
}
