import Foundation
@testable import ProjectZD8

/// 走行ルートのローカル同期 Repository をメモリ上で再現し、呼び出しを順に記録して、メソッドごと・セッションごとに失敗を注入できる Fake です。
///
/// `uploadCandidates` は契約より広く、アカウントが一致する登録済みセッションをすべて(空・restored を含めて)登録順に返します。
/// 送信ユースケースがポリシーで絞り込むことを検証できるようにするためです。
nonisolated final class ConnectionSessionLocationTrackSyncRepositoryFake: ConnectionSessionLocationTrackSyncRepository,
    @unchecked Sendable {
    /// 記録する呼び出しです。
    nonisolated enum Call: Equatable, Sendable {
        /// 送信候補の取得です。
        case uploadCandidates(accountIdentifier: String)
        /// 軌跡の読み取りです。
        case track(ConnectionSessionID)
        /// 同期記録の読み取りです。
        case syncRecord(ConnectionSessionID)
        /// 送信済みの記録です。
        case markUploaded(
            sessionID: ConnectionSessionID,
            manifestDigest: String,
            watermark: ConnectionSessionLocationTrackWatermark,
            date: Date
        )
        /// 復元した軌跡での置き換えです。
        case replaceWithRestoredTrack(VerifiedConnectionSessionLocationTrack, date: Date)
    }

    /// 失敗を注入できるメソッドです。
    nonisolated enum Method: Hashable, Sendable {
        /// `uploadCandidates(for:)`。
        case uploadCandidates
        /// `track(for:)`。
        case track
        /// `syncRecord(for:)`。
        case syncRecord
        /// `markUploaded(sessionID:manifestDigest:watermark:at:)`。
        case markUploaded
        /// `replaceWithRestoredTrack(_:at:)`。
        case replaceWithRestoredTrack
    }

    /// 失敗の注入先(メソッドと、対象のセッション。`nil` は全セッション)です。
    private nonisolated struct FailureKey: Hashable, Sendable {
        /// 対象のメソッドです。
        let method: Method
        /// 対象のセッションです(`nil` は全セッション)。
        let sessionID: ConnectionSessionID?
    }

    /// 保持内容と失敗指定を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、登録順のセッション ID です。
    private var storedSessionOrder: [ConnectionSessionID] = []
    /// ロックで保護した、セッションごとのアカウント識別子です。
    private var storedAccounts: [ConnectionSessionID: String] = [:]
    /// ロックで保護した、セッションごとの軌跡です。
    private var storedTracks: [ConnectionSessionID: ConnectionSessionLocationTrack] = [:]
    /// ロックで保護した、セッションごとの同期記録です。
    private var storedSyncRecords: [ConnectionSessionID: ConnectionSessionLocationTrackSyncRecord] = [:]
    /// ロックで保護した、呼び出しの記録です(呼ばれた順)。
    private var storedCalls: [Call] = []
    /// ロックで保護した、注入された失敗です。
    private var storedFailures: [FailureKey: any Error] = [:]
    /// ロックで保護した、軌跡を読む直前に呼ぶ動作です。
    private var storedOnTrackRead: (@Sendable (ConnectionSessionID) -> Void)?

    /// 空の Fake を生成します。
    ///
    /// 責務: セッションも失敗も登録されていない状態を構築します。
    init() {}

    /// 呼ばれた順の呼び出しの記録です。
    var calls: [Call] {
        lock.withLock { storedCalls }
    }

    /// 送信済みとして記録された呼び出しだけを、呼ばれた順に返します。
    var markUploadedCalls: [Call] {
        calls.filter { if case .markUploaded = $0 { true } else { false } }
    }

    /// 復元での置き換えの呼び出しだけを、呼ばれた順に返します。
    var replaceCalls: [Call] {
        calls.filter { if case .replaceWithRestoredTrack = $0 { true } else { false } }
    }

    /// 終了済みのセッションを1件登録します。
    ///
    /// 責務: アカウント・軌跡・同期記録を登録順の末尾へ保存します。
    /// - Parameters:
    ///   - track: セッションの軌跡(セッション ID は軌跡のものを使います)。
    ///   - accountIdentifier: セッションのアカウント識別子。
    ///   - syncRecord: 既にある同期記録。
    func addSession(
        _ track: ConnectionSessionLocationTrack,
        accountIdentifier: String,
        syncRecord: ConnectionSessionLocationTrackSyncRecord? = nil
    ) {
        lock.withLock {
            storedSessionOrder.append(track.sessionID)
            storedAccounts[track.sessionID] = accountIdentifier
            storedTracks[track.sessionID] = track
            storedSyncRecords[track.sessionID] = syncRecord
        }
    }

    /// 登録済みセッションの軌跡を置き換えます(送信後に点が増えた状況などに使います)。
    ///
    /// 責務: 軌跡のセッション ID の保存内容だけを置き換えます。
    /// - Parameter track: 新しい軌跡。
    func setTrack(_ track: ConnectionSessionLocationTrack) {
        lock.withLock { storedTracks[track.sessionID] = track }
    }

    /// 失敗の注入を設定または解除します。
    ///
    /// 責務: 指定したメソッド(とセッション)の呼び出しで投げるエラーを置き換えます。
    /// - Parameters:
    ///   - error: 投げるエラー。`nil` で解除します。
    ///   - method: 対象のメソッド。
    ///   - sessionID: 対象のセッション。`nil` は全セッション。
    func setFailure(_ error: (any Error)?, for method: Method, sessionID: ConnectionSessionID? = nil) {
        lock.withLock { storedFailures[FailureKey(method: method, sessionID: sessionID)] = error }
    }

    /// 軌跡を読む直前に呼ぶ動作を設定します(候補の取得と読み取りの間に点が増える状況などに使います)。
    ///
    /// 責務: `track(for:)` がロックの外で呼ぶ動作を置き換えます。
    /// - Parameter hook: 呼ぶ動作。`nil` で解除します。
    func setOnTrackRead(_ hook: (@Sendable (ConnectionSessionID) -> Void)?) {
        lock.withLock { storedOnTrackRead = hook }
    }

    /// 保存中の軌跡を返します(呼び出しとして記録しません)。
    ///
    /// 責務: テストの確認用に、セッションの現在の軌跡を返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 保存中の軌跡。未登録なら `nil`。
    func storedTrack(for sessionID: ConnectionSessionID) -> ConnectionSessionLocationTrack? {
        lock.withLock { storedTracks[sessionID] }
    }

    /// 保存中の同期記録を返します(呼び出しとして記録しません)。
    ///
    /// 責務: テストの確認用に、セッションの現在の同期記録を返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 保存中の同期記録。無ければ `nil`。
    func storedSyncRecord(for sessionID: ConnectionSessionID) -> ConnectionSessionLocationTrackSyncRecord? {
        lock.withLock { storedSyncRecords[sessionID] }
    }

    /// アカウントが一致する登録済みセッションを登録順に返します。
    ///
    /// 責務: 呼び出しを記録し、失敗の注入があれば投げ、各セッションの現在の水位と同期記録を候補にします。
    /// - Parameter accountIdentifier: 対象のアカウント識別子。
    /// - Returns: 候補(空・restored を含む)。
    /// - Throws: 注入されたエラー。
    func uploadCandidates(for accountIdentifier: String) throws -> [ConnectionSessionLocationTrackUploadCandidate] {
        try lock.withLock {
            storedCalls.append(.uploadCandidates(accountIdentifier: accountIdentifier))
            try throwInjectedFailure(.uploadCandidates, sessionID: nil)
            return storedSessionOrder.filter { storedAccounts[$0] == accountIdentifier }.map { sessionID in
                ConnectionSessionLocationTrackUploadCandidate(
                    sessionID: sessionID,
                    localWatermark: storedTracks[sessionID]?.watermark ?? .empty,
                    syncRecord: storedSyncRecords[sessionID]
                )
            }
        }
    }

    /// セッションの軌跡を返します。
    ///
    /// 責務: 呼び出しを記録し、読む直前の動作を呼び、失敗の注入があれば投げ、保存中の軌跡(無ければ空)を返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 保存中の軌跡。
    /// - Throws: 注入されたエラー。
    func track(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrack {
        let hook = lock.withLock {
            storedCalls.append(.track(sessionID))
            return storedOnTrackRead
        }
        hook?(sessionID)
        return try lock.withLock {
            try throwInjectedFailure(.track, sessionID: sessionID)
            return storedTracks[sessionID] ?? ConnectionSessionLocationTrack(sessionID: sessionID, samples: [], events: [])
        }
    }

    /// セッションの同期記録を返します。
    ///
    /// 責務: 呼び出しを記録し、失敗の注入があれば投げ、保存中の同期記録を返します。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: 同期記録。無ければ `nil`。
    /// - Throws: 注入されたエラー。
    func syncRecord(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrackSyncRecord? {
        try lock.withLock {
            storedCalls.append(.syncRecord(sessionID))
            try throwInjectedFailure(.syncRecord, sessionID: sessionID)
            return storedSyncRecords[sessionID]
        }
    }

    /// 送信済みの同期記録を上書き保存します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗・未登録・restored の行を契約どおり投げ、それ以外は uploaded の記録を保存します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - manifestDigest: 送信した内容の digest。
    ///   - watermark: 送信した軌跡の水位。
    ///   - date: 送信した日時。
    /// - Throws: 注入されたエラー、または `ConnectionSessionRepositoryError.integrityConflict`。
    func markUploaded(
        sessionID: ConnectionSessionID,
        manifestDigest: String,
        watermark: ConnectionSessionLocationTrackWatermark,
        at date: Date
    ) throws {
        try lock.withLock {
            storedCalls.append(
                .markUploaded(sessionID: sessionID, manifestDigest: manifestDigest, watermark: watermark, date: date)
            )
            try throwInjectedFailure(.markUploaded, sessionID: sessionID)
            guard storedAccounts[sessionID] != nil, storedSyncRecords[sessionID]?.origin != .restored else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            storedSyncRecords[sessionID] = ConnectionSessionLocationTrackSyncRecord(
                sessionID: sessionID,
                origin: .uploaded,
                manifestDigest: manifestDigest,
                watermark: watermark,
                syncedAt: date
            )
        }
    }

    /// 復元した軌跡でセッションの軌跡を置き換え、restored の同期記録を保存します。
    ///
    /// 責務: 呼び出しを記録し、注入された失敗・未登録・この端末で記録した行を契約どおり投げ、それ以外は置き換えます。
    /// - Parameters:
    ///   - verified: 検証済みの軌跡と digest。
    ///   - date: 復元した日時。
    /// - Throws: 注入されたエラー、または `ConnectionSessionRepositoryError.integrityConflict`。
    func replaceWithRestoredTrack(_ verified: VerifiedConnectionSessionLocationTrack, at date: Date) throws {
        let sessionID = verified.track.sessionID
        try lock.withLock {
            storedCalls.append(.replaceWithRestoredTrack(verified, date: date))
            try throwInjectedFailure(.replaceWithRestoredTrack, sessionID: sessionID)
            guard storedAccounts[sessionID] != nil, !hasLocallyRecordedRows(sessionID) else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            storedTracks[sessionID] = verified.track
            storedSyncRecords[sessionID] = ConnectionSessionLocationTrackSyncRecord(
                sessionID: sessionID,
                origin: .restored,
                manifestDigest: verified.manifestDigest,
                watermark: verified.track.watermark,
                syncedAt: date
            )
        }
    }

    /// この端末で記録した行があるかを判定します(ロックの内側で呼びます)。
    ///
    /// 責務: uploaded の記録がある、または記録が無いのに行がある場合を真とします。
    /// - Parameter sessionID: 対象の接続セッション。
    /// - Returns: この端末で記録した行があれば `true`。
    private func hasLocallyRecordedRows(_ sessionID: ConnectionSessionID) -> Bool {
        switch storedSyncRecords[sessionID]?.origin {
        case .uploaded: true
        case .restored: false
        case nil: !(storedTracks[sessionID]?.isEmpty ?? true)
        }
    }

    /// 注入された失敗があれば投げます(ロックの内側で呼びます)。
    ///
    /// 責務: セッション指定の失敗を優先し、無ければ全セッション指定の失敗を投げます。
    /// - Parameters:
    ///   - method: 呼ばれたメソッド。
    ///   - sessionID: 呼び出しの対象セッション。
    /// - Throws: 注入されたエラー。
    private func throwInjectedFailure(_ method: Method, sessionID: ConnectionSessionID?) throws {
        if let sessionID, let error = storedFailures[FailureKey(method: method, sessionID: sessionID)] {
            throw error
        }
        if let error = storedFailures[FailureKey(method: method, sessionID: nil)] {
            throw error
        }
    }
}
