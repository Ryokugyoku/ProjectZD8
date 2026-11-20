import Foundation

/// 未送信または送信後に変化した走行ルート(位置の軌跡)を iCloud へアップロードします。iPhone だけに配線します。
///
/// 順序: 削除済みセッションの取得(失敗したら何も送らない)→ 削除済みの軌跡の掃除(失敗しても続ける)→
/// アカウント削除の確認 → 候補ごとの送信(失敗しても残りを続ける)。最後に、起きた順で最初のエラーを投げます。
/// 取消(`CancellationError` と `Task` のキャンセル)は待たずにすぐ投げます。
@MainActor
struct UploadConnectionSessionLocationTracksUseCase {
    /// ローカルの軌跡と同期記録の読み書き先です。
    private let syncRepository: any ConnectionSessionLocationTrackSyncRepository
    /// iCloud 上の軌跡の保存・削除先です。
    private let cloudRepository: any ConnectionSessionLocationTrackCloudRepository
    /// 全端末で削除済みのセッションIDを返す処理です。
    private let deletedSessionIDs: @MainActor (String) async throws -> Set<ConnectionSessionID>
    /// アカウントが削除されていないことを確かめる処理です。削除済みなら投げます。
    private let accountDeletionCheck: (@MainActor (String) async throws -> Void)?
    /// 水位と同期記録から送信の要否を決める判定です。
    private let policy: ConnectionSessionLocationTrackSyncStatusPolicy
    /// 送信を記録する時刻を返す処理です。
    private let now: () -> Date

    /// 依存する保存先・確認処理・判定・時刻を固定して生成します。
    ///
    /// 責務: アップロードに必要な境界を注入された値で構成します。
    /// - Parameters:
    ///   - syncRepository: ローカルの軌跡と同期記録の読み書き先。
    ///   - cloudRepository: iCloud 上の軌跡の保存・削除先。
    ///   - deletedSessionIDs: 全端末で削除済みのセッションIDを返す処理。
    ///   - accountDeletionCheck: アカウント削除の確認。削除済みなら投げる。
    ///   - policy: 送信の要否の判定。
    ///   - now: 送信を記録する時刻を返す処理。
    init(
        syncRepository: any ConnectionSessionLocationTrackSyncRepository,
        cloudRepository: any ConnectionSessionLocationTrackCloudRepository,
        deletedSessionIDs: @escaping @MainActor (String) async throws -> Set<ConnectionSessionID>,
        accountDeletionCheck: (@MainActor (String) async throws -> Void)? = nil,
        policy: ConnectionSessionLocationTrackSyncStatusPolicy = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.syncRepository = syncRepository
        self.cloudRepository = cloudRepository
        self.deletedSessionIDs = deletedSessionIDs
        self.accountDeletionCheck = accountDeletionCheck
        self.policy = policy
        self.now = now
    }

    /// 削除済みの軌跡を掃除し、送信が必要な軌跡をアップロードします。
    ///
    /// 責務: 掃除・確認・送信を決まった順に実行し、途中の失敗を最後に1件のエラーとして返します。
    /// - Parameter accountIdentifier: 対象アカウント。
    /// - Returns: 送ったセッション(送った順)と掃除したセッション。
    /// - Throws: 空のアカウントは `.invalidState`。削除済みIDの取得とアカウント削除の確認の失敗はすぐ投げ、
    ///   掃除と送信の失敗は残りを続けてから最初のものを投げます。取消はすぐ投げます。
    func execute(accountIdentifier: String) async throws -> ConnectionSessionLocationTrackUploadReport {
        guard !accountIdentifier.isEmpty else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let deleted = try await deletedSessionIDs(accountIdentifier)
        var firstFailure: (any Error)?
        let purged = try await purge(deleted, accountIdentifier: accountIdentifier, firstFailure: &firstFailure)
        try await accountDeletionCheck?(accountIdentifier)
        let uploaded = try await uploadPending(
            excluding: deleted,
            accountIdentifier: accountIdentifier,
            firstFailure: &firstFailure
        )
        if let firstFailure {
            throw firstFailure
        }
        return ConnectionSessionLocationTrackUploadReport(uploadedSessionIDs: uploaded, purgedSessionIDs: purged)
    }

    /// iCloud に残っている削除済みセッションの軌跡を消します。
    ///
    /// 責務: iCloud 上のセッションと削除済みの積集合だけを削除し、失敗は記録して続けます。
    /// - Parameters:
    ///   - deleted: 全端末で削除済みのセッションID。
    ///   - accountIdentifier: 対象アカウント。
    ///   - firstFailure: 最初の失敗の記録先。
    /// - Returns: 削除できたセッションID。
    /// - Throws: 取消だけをすぐ投げます。
    private func purge(
        _ deleted: Set<ConnectionSessionID>,
        accountIdentifier: String,
        firstFailure: inout (any Error)?
    ) async throws -> Set<ConnectionSessionID> {
        let remote: Set<ConnectionSessionID>
        do {
            remote = try await cloudRepository.remoteSessionIDs(for: accountIdentifier)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            firstFailure = firstFailure ?? error
            return []
        }
        var purged = Set<ConnectionSessionID>()
        for sessionID in Self.ordered(remote.intersection(deleted)) {
            try Task.checkCancellation()
            do {
                try await cloudRepository.delete(sessionID: sessionID, for: accountIdentifier)
                purged.insert(sessionID)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        return purged
    }

    /// 送信が必要な候補を順にアップロードします。
    ///
    /// 責務: 候補の取得とセッションごとの送信を行い、失敗は記録して残りを続けます。
    /// - Parameters:
    ///   - deleted: 送らない削除済みのセッションID。
    ///   - accountIdentifier: 対象アカウント。
    ///   - firstFailure: 最初の失敗の記録先。
    /// - Returns: 送ったセッションID(送った順)。
    /// - Throws: 取消だけをすぐ投げます。
    private func uploadPending(
        excluding deleted: Set<ConnectionSessionID>,
        accountIdentifier: String,
        firstFailure: inout (any Error)?
    ) async throws -> [ConnectionSessionID] {
        let sessionIDs: [ConnectionSessionID]
        do {
            sessionIDs = try sessionIDsNeedingUpload(accountIdentifier: accountIdentifier, excluding: deleted)
        } catch {
            firstFailure = firstFailure ?? error
            return []
        }
        var uploaded: [ConnectionSessionID] = []
        for sessionID in sessionIDs {
            try Task.checkCancellation()
            do {
                if try await uploadSession(sessionID, accountIdentifier: accountIdentifier) {
                    uploaded.append(sessionID)
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        return uploaded
    }

    /// 送信が必要なセッションを返します。
    ///
    /// 責務: 候補を、判定で送信が必要かつ削除済みでないものに絞ります。
    /// - Parameters:
    ///   - accountIdentifier: 対象アカウント。
    ///   - deleted: 除く削除済みのセッションID。
    /// - Returns: 送信が必要なセッションID(候補の順)。
    /// - Throws: 候補の取得の失敗。
    private func sessionIDsNeedingUpload(
        accountIdentifier: String,
        excluding deleted: Set<ConnectionSessionID>
    ) throws -> [ConnectionSessionID] {
        try syncRepository.uploadCandidates(for: accountIdentifier)
            .filter { candidate in
                !deleted.contains(candidate.sessionID)
                    && policy.status(localWatermark: candidate.localWatermark, record: candidate.syncRecord).needsUpload
            }
            .map(\.sessionID)
    }

    /// 1セッションの軌跡を送信し、送信済みとして記録します。
    ///
    /// 責務: 一貫した軌跡を読み、空でなければ送り、読んだ時点の水位で同期記録を更新します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 送った時は true。軌跡が空で飛ばした時は false。
    /// - Throws: 読取・送信・記録の失敗。
    private func uploadSession(_ sessionID: ConnectionSessionID, accountIdentifier: String) async throws -> Bool {
        let track = try syncRepository.track(for: sessionID)
        guard !track.isEmpty else {
            return false
        }
        let digest = try await cloudRepository.upload(track, for: accountIdentifier)
        try syncRepository.markUploaded(
            sessionID: sessionID,
            manifestDigest: digest,
            watermark: track.watermark,
            at: now()
        )
        return true
    }

    /// セッションIDを決まった順に並べます。
    ///
    /// 責務: 集合の走査順に依存しないよう、UUID の文字列順へ並べます。
    /// - Parameter sessionIDs: 並べるセッションID。
    /// - Returns: 並べたセッションID。
    private static func ordered(_ sessionIDs: Set<ConnectionSessionID>) -> [ConnectionSessionID] {
        sessionIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }
}
