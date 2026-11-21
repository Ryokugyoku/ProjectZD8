/// 軌跡を iCloud(CloudKit)へ保存・取得・削除する能力です。
@MainActor protocol ConnectionSessionLocationTrackCloudRepository {
    /// 軌跡を保存します。
    ///
    /// 責務: 同じ recordName へ上書き保存し、Asset バイト列の SHA-256 を返します。
    /// - Parameters:
    ///   - track: 送る軌跡。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: manifestDigest。
    /// - Throws: 空の軌跡は `ConnectionSessionRepositoryError.invalidState`。
    func upload(_ track: ConnectionSessionLocationTrack, for accountIdentifier: String) async throws -> String

    /// レコードの概要を返します。
    ///
    /// 責務: Asset を取得せずに manifest を読みます。
    /// - Returns: 概要。nil はレコード無し。
    func remoteManifest(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackRemoteManifest?

    /// 軌跡を取得します。
    ///
    /// 責務: Asset を取得し、digest と内容を検証して返します。
    /// - Returns: 検証済みの軌跡。nil はレコード無し。
    /// - Throws: 検証失敗は `.integrityConflict`、新しい版は `ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat`。
    func download(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionLocationTrack?

    /// iCloud にある軌跡のセッションIDを返します。
    ///
    /// 責務: 自分のアカウントの軌跡レコードのセッションID を全件列挙します。
    func remoteSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID>

    /// 1セッションの軌跡を削除します。
    ///
    /// 責務: レコードがあれば削除します。無くても成功する(冪等)。
    func delete(sessionID: ConnectionSessionID, for accountIdentifier: String) async throws

    /// アカウントの軌跡をすべて削除します。
    ///
    /// 責務: 自分のアカウントの軌跡レコードをすべて削除します。
    func deleteAll(for accountIdentifier: String) async throws
}
