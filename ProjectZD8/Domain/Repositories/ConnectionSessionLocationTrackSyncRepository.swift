import Foundation

/// 軌跡のローカルの同期記録と、同期のための読み書きを担う能力です。
///
/// 例外の約束: セッション不在・制約違反・保存値をDomainへ復元できない場合は
/// `ConnectionSessionRepositoryError.integrityConflict`、それ以外の保存・読取失敗は `.unavailable`。
nonisolated protocol ConnectionSessionLocationTrackSyncRepository: Sendable {
    /// アップロード候補を返します。
    ///
    /// 責務: 終了済み・アカウント一致・サンプルか事象が1件以上・origin が restored ではない、の全てを満たすセッションを水位つきで返します。
    /// - Parameter accountIdentifier: 対象アカウント。
    /// - Returns: 候補。無ければ空配列。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外は `.unavailable`。
    func uploadCandidates(for accountIdentifier: String) throws -> [ConnectionSessionLocationTrackUploadCandidate]

    /// セッションの軌跡を返します。
    ///
    /// 責務: 1回の読取 transaction で一貫した軌跡を返します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: 軌跡。行が無ければ空の軌跡。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外は `.unavailable`。
    func track(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrack

    /// セッションの同期記録を返します。
    ///
    /// 責務: 保存済みの同期記録を1件読みます。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: 同期記録。無ければ nil。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外は `.unavailable`。
    func syncRecord(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrackSyncRecord?

    /// 送信済みとして記録します。
    ///
    /// 責務: origin = uploaded で同期記録を上書き保存(upsert)します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - manifestDigest: 送信した Asset バイト列の SHA-256。
    ///   - watermark: 送信した軌跡を読んだ時点の水位。
    ///   - date: 同期した時刻。
    /// - Throws: セッション不在、または origin が restored の行がある場合は `.integrityConflict`、それ以外は `.unavailable`。
    func markUploaded(
        sessionID: ConnectionSessionID,
        manifestDigest: String,
        watermark: ConnectionSessionLocationTrackWatermark,
        at date: Date
    ) throws

    /// iCloud から取得した軌跡で置き換えます。
    ///
    /// 責務: 1つの transaction で、そのセッションの軌跡行を消し、番号どおりに入れ直し、origin = restored を保存します。
    /// この端末で記録した行がある(同期記録が無い、または uploaded)場合は何も変えません。
    /// - Parameters:
    ///   - verified: 照合済みの軌跡。
    ///   - date: 復元した時刻。
    /// - Throws: セッション不在、この端末で記録した行がある、制約違反は `.integrityConflict`、それ以外は `.unavailable`。
    func replaceWithRestoredTrack(_ verified: VerifiedConnectionSessionLocationTrack, at date: Date) throws
}
