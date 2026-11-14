import Foundation

/// 連続取得区間の間の空白を永続化する能力です。
nonisolated protocol ConnectionSessionGapRepository: Sendable {
    /// 取得の空白を新規保存します。
    ///
    /// 責務: 1件の空白を指定セッションへ追加します。終了情報を持つ空白もそのまま保存します。
    /// - Parameters:
    ///   - gap: 保存する空白。
    ///   - sessionID: 空白を所有する接続セッション。
    /// - Throws: 番号重複・前後区間の不在・範囲外の値・開始より前の終了時刻は
    ///   `ConnectionSessionRepositoryError.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func saveGap(_ gap: ConnectionSessionGap, for sessionID: ConnectionSessionID) throws

    /// 未終了の空白へ終了時刻と直後の区間を確定します。
    ///
    /// 責務: 1件の未終了の空白を終了時刻と任意の後続区間番号を持つ終了済み状態へ遷移させます。
    /// - Parameters:
    ///   - gapOrdinal: 終了する空白の番号。
    ///   - sessionID: 空白を所有する接続セッション。
    ///   - endedAt: 空白が終わった実時間。
    ///   - followingSegmentOrdinal: 空白の直後に始まった区間の番号。取得を再開せずに終わる場合は `nil`。
    /// - Throws: 空白不在または終了済みは `ConnectionSessionRepositoryError.invalidState`、
    ///   後続区間の不在・開始より前の終了時刻は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func finishGap(
        ordinal gapOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        followingSegmentOrdinal: Int?
    ) throws

    /// セッションの空白を欠損番号順で返します。
    ///
    /// 責務: 1件のセッションに保存された全空白を安定順で復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `gapOrdinal` 昇順の空白。空白がないセッションでは空配列。
    /// - Throws: 保存値をDomainへ復元できない場合は `ConnectionSessionRepositoryError.integrityConflict`、
    ///   それ以外の読取失敗は `.unavailable`。
    func gaps(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionGap]
}
