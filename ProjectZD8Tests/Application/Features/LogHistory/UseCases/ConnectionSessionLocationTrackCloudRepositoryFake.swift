import Foundation
@testable import ProjectZD8

/// 走行ルートの iCloud Repository をメモリ上のレコード(セッション ID → 軌跡と digest)で再現し、
/// 呼び出しを順に記録して、メソッドごと・セッションごとに失敗を注入できる Fake です。
@MainActor
final class ConnectionSessionLocationTrackCloudRepositoryFake: ConnectionSessionLocationTrackCloudRepository {
    /// 記録する呼び出しです。
    enum Call: Equatable {
        /// 軌跡の送信です。
        case upload(sessionID: ConnectionSessionID, accountIdentifier: String)
        /// 概要の取得です。
        case remoteManifest(sessionID: ConnectionSessionID, accountIdentifier: String)
        /// 軌跡の取得です。
        case download(sessionID: ConnectionSessionID, accountIdentifier: String)
        /// レコードのあるセッション ID の取得です。
        case remoteSessionIDs(accountIdentifier: String)
        /// 1セッションの削除です。
        case delete(sessionID: ConnectionSessionID, accountIdentifier: String)
        /// アカウントの全削除です。
        case deleteAll(accountIdentifier: String)
    }

    /// 失敗を注入できるメソッドです。
    enum Method: Hashable {
        /// `upload(_:for:)`。
        case upload
        /// `remoteManifest(sessionID:for:)`。
        case remoteManifest
        /// `download(sessionID:for:)`。
        case download
        /// `remoteSessionIDs(for:)`。
        case remoteSessionIDs
        /// `delete(sessionID:for:)`。
        case delete
        /// `deleteAll(for:)`。
        case deleteAll
    }

    /// メモリ上のレコード1件です。
    struct StoredRecord: Equatable {
        /// レコードのアカウント識別子です。
        let accountIdentifier: String
        /// 保存された軌跡です。
        let track: ConnectionSessionLocationTrack
        /// 保存された内容の digest です。
        let digest: String
    }

    /// 失敗の注入先(メソッドと、対象のセッション。`nil` は全セッション)です。
    private struct FailureKey: Hashable {
        /// 対象のメソッドです。
        let method: Method
        /// 対象のセッションです(`nil` は全セッション)。
        let sessionID: ConnectionSessionID?
    }

    /// セッション ID ごとのレコードです。
    private(set) var records: [ConnectionSessionID: StoredRecord] = [:]
    /// 呼ばれた順の呼び出しの記録です。
    private(set) var calls: [Call] = []
    /// 送信に成功した軌跡です(送った順)。
    private(set) var uploadedTracks: [ConnectionSessionLocationTrack] = []
    /// 呼び出しのたびに、記録の後で通知する動作です(他の Fake との順序の検証に使います)。
    var onCall: (@MainActor (Call) -> Void)?
    /// 注入された失敗です。
    private var failures: [FailureKey: any Error] = [:]
    /// 次の送信で返す digest の番号です。
    private var nextDigestNumber = 0

    /// 空の Fake を生成します。
    ///
    /// 責務: レコードも失敗も無い状態を構築します。
    init() {}

    /// レコードを1件置きます。
    ///
    /// 責務: 他の端末が送った状況を作るため、呼び出しとして記録せずにレコードを保存します。
    /// - Parameters:
    ///   - track: 保存する軌跡。
    ///   - digest: 保存する digest。
    ///   - accountIdentifier: レコードのアカウント識別子。
    func seedRecord(_ track: ConnectionSessionLocationTrack, digest: String, accountIdentifier: String) {
        records[track.sessionID] = StoredRecord(accountIdentifier: accountIdentifier, track: track, digest: digest)
    }

    /// 失敗の注入を設定または解除します。
    ///
    /// 責務: 指定したメソッド(とセッション)の呼び出しで投げるエラーを置き換えます。
    /// - Parameters:
    ///   - error: 投げるエラー。`nil` で解除します。
    ///   - method: 対象のメソッド。
    ///   - sessionID: 対象のセッション。`nil` は全セッション。
    func setFailure(_ error: (any Error)?, for method: Method, sessionID: ConnectionSessionID? = nil) {
        failures[FailureKey(method: method, sessionID: sessionID)] = error
    }

    /// 送信の呼び出しだけを、呼ばれた順に返します。
    ///
    /// 責務: 呼び出しの記録から送信を抜き出し、対象のセッション ID を返します。
    /// - Returns: 送信が呼ばれたセッション ID(失敗を含む)。
    func uploadCallSessionIDs() -> [ConnectionSessionID] {
        calls.compactMap { if case let .upload(sessionID, _) = $0 { sessionID } else { nil } }
    }

    /// 削除の呼び出しだけを返します。
    ///
    /// 責務: 呼び出しの記録から1セッションの削除を抜き出し、対象のセッション ID を返します。
    /// - Returns: 削除が呼ばれたセッション ID(失敗を含む。呼ばれた順)。
    func deleteCallSessionIDs() -> [ConnectionSessionID] {
        calls.compactMap { if case let .delete(sessionID, _) = $0 { sessionID } else { nil } }
    }

    /// 軌跡を保存し、新しい digest を返します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗・空の軌跡を投げ、それ以外は同じ ID のレコードへ上書きします。
    /// - Parameters:
    ///   - track: 送る軌跡。
    ///   - accountIdentifier: 送り先のアカウント識別子。
    /// - Returns: 送信ごとに異なる digest。
    /// - Throws: 注入されたエラー、または空の軌跡なら `ConnectionSessionRepositoryError.invalidState`。
    func upload(_ track: ConnectionSessionLocationTrack, for accountIdentifier: String) async throws -> String {
        try record(.upload(sessionID: track.sessionID, accountIdentifier: accountIdentifier), .upload, track.sessionID)
        guard !track.isEmpty else { throw ConnectionSessionRepositoryError.invalidState }
        nextDigestNumber += 1
        let digest = "cloud-digest-\(nextDigestNumber)"
        records[track.sessionID] = StoredRecord(accountIdentifier: accountIdentifier, track: track, digest: digest)
        uploadedTracks.append(track)
        return digest
    }

    /// レコードの概要を返します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗を投げ、アカウントが一致するレコードの digest と件数を返します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象のアカウント識別子。
    /// - Returns: 概要。レコードが無ければ `nil`。
    /// - Throws: 注入されたエラー。
    func remoteManifest(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackRemoteManifest? {
        try record(.remoteManifest(sessionID: sessionID, accountIdentifier: accountIdentifier), .remoteManifest, sessionID)
        return storedRecord(sessionID, accountIdentifier).map {
            ConnectionSessionLocationTrackRemoteManifest(
                sessionID: sessionID,
                manifestDigest: $0.digest,
                sampleCount: $0.track.samples.count,
                eventCount: $0.track.events.count
            )
        }
    }

    /// レコードの軌跡を返します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗を投げ、アカウントが一致するレコードの軌跡と digest を返します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象のアカウント識別子。
    /// - Returns: 検証済みの軌跡。レコードが無ければ `nil`。
    /// - Throws: 注入されたエラー。
    func download(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionLocationTrack? {
        try record(.download(sessionID: sessionID, accountIdentifier: accountIdentifier), .download, sessionID)
        return storedRecord(sessionID, accountIdentifier).map {
            VerifiedConnectionSessionLocationTrack(track: $0.track, manifestDigest: $0.digest)
        }
    }

    /// アカウントのレコードがあるセッション ID を返します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗を投げ、アカウントが一致するレコードの ID を返します。
    /// - Parameter accountIdentifier: 対象のアカウント識別子。
    /// - Returns: セッション ID の集合。
    /// - Throws: 注入されたエラー。
    func remoteSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> {
        try record(.remoteSessionIDs(accountIdentifier: accountIdentifier), .remoteSessionIDs, nil)
        return Set(records.filter { $0.value.accountIdentifier == accountIdentifier }.keys)
    }

    /// 1セッションのレコードを消します(無くても成功します)。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗を投げ、アカウントが一致するレコードを消します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象のアカウント識別子。
    /// - Throws: 注入されたエラー。
    func delete(sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        try record(.delete(sessionID: sessionID, accountIdentifier: accountIdentifier), .delete, sessionID)
        if storedRecord(sessionID, accountIdentifier) != nil {
            records[sessionID] = nil
        }
    }

    /// アカウントのレコードをすべて消します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗を投げ、アカウントが一致するレコードをすべて消します。
    /// - Parameter accountIdentifier: 対象のアカウント識別子。
    /// - Throws: 注入されたエラー。
    func deleteAll(for accountIdentifier: String) async throws {
        try record(.deleteAll(accountIdentifier: accountIdentifier), .deleteAll, nil)
        records = records.filter { $0.value.accountIdentifier != accountIdentifier }
    }

    /// 呼び出しを記録して通知し、注入された失敗があれば投げます。
    ///
    /// 責務: 記録・通知・失敗の注入を、全メソッドで同じ順序に行います。
    /// - Parameters:
    ///   - call: 記録する呼び出し。
    ///   - method: 呼ばれたメソッド。
    ///   - sessionID: 呼び出しの対象セッション。
    /// - Throws: セッション指定の失敗を優先し、無ければ全セッション指定の失敗。
    private func record(_ call: Call, _ method: Method, _ sessionID: ConnectionSessionID?) throws {
        calls.append(call)
        onCall?(call)
        if let sessionID, let error = failures[FailureKey(method: method, sessionID: sessionID)] {
            throw error
        }
        if let error = failures[FailureKey(method: method, sessionID: nil)] {
            throw error
        }
    }

    /// アカウントが一致するレコードを返します。
    ///
    /// 責務: 別のアカウントのレコードを見えないものとして扱います。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象のアカウント識別子。
    /// - Returns: レコード。無ければ `nil`。
    private func storedRecord(_ sessionID: ConnectionSessionID, _ accountIdentifier: String) -> StoredRecord? {
        guard let stored = records[sessionID], stored.accountIdentifier == accountIdentifier else { return nil }
        return stored
    }
}
