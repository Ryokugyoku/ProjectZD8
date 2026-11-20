import Foundation

/// 1セッションの走行ルート(位置の軌跡)を、ローカルか iCloud から表示用に用意します。
///
/// この端末で記録した軌跡は通信せずに返します。以前に復元した軌跡は iCloud の digest と照合し、
/// 変わっていれば取り直します。照合できない時は `restoredEarlier(isVerifiedLatest: false)` を値で返し、成功に潰しません。
/// ローカルに無い時は iCloud から取得し、レコードが無ければ `.notInCloud` を返します(空の軌跡とは区別します)。
@MainActor
struct LoadConnectionSessionLocationTrackUseCase {
    /// ローカルの軌跡と同期記録の読み書き先です。
    private let syncRepository: any ConnectionSessionLocationTrackSyncRepository
    /// iCloud 上の軌跡の取得元です。
    private let cloudRepository: any ConnectionSessionLocationTrackCloudRepository
    /// 復元を記録する時刻を返す処理です。
    private let now: () -> Date

    /// 依存する保存先と時刻を固定して生成します。
    ///
    /// 責務: 取得と復元に必要な境界を注入された値で構成します。
    /// - Parameters:
    ///   - syncRepository: ローカルの軌跡と同期記録の読み書き先。
    ///   - cloudRepository: iCloud 上の軌跡の取得元。
    ///   - now: 復元を記録する時刻を返す処理。
    init(
        syncRepository: any ConnectionSessionLocationTrackSyncRepository,
        cloudRepository: any ConnectionSessionLocationTrackCloudRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.syncRepository = syncRepository
        self.cloudRepository = cloudRepository
        self.now = now
    }

    /// 軌跡を用意します。
    ///
    /// 責務: 同期記録の由来とローカルの有無から、そのまま返す・照合する・取得する、のどれかへ振り分けます。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 使える軌跡とその出どころ、または iCloud にも無いこと。
    /// - Throws: 空のアカウントは `.invalidState`。ローカルの読み書きの失敗、ローカルに無い軌跡の取得の失敗、取消。
    func execute(
        sessionID: ConnectionSessionID,
        accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackAvailability {
        guard !accountIdentifier.isEmpty else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let record = try syncRepository.syncRecord(for: sessionID)
        let local = try syncRepository.track(for: sessionID)
        if let record, record.origin == .restored {
            return try await refreshRestored(local, record: record, accountIdentifier: accountIdentifier)
        }
        if !local.isEmpty {
            return .available(local, .recordedOnThisDevice)
        }
        return try await downloadMissing(sessionID, accountIdentifier: accountIdentifier)
    }

    /// 以前に復元した軌跡を iCloud と照合し、変わっていれば取り直します。
    ///
    /// 責務: digest が同じなら確認済みとして、違えば取得して復元し、照合や取得ができなければ未確認として返します。
    /// - Parameters:
    ///   - local: ローカルにある復元済みの軌跡。
    ///   - record: 復元の同期記録。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 使える軌跡とその出どころ。
    /// - Throws: 復元の書き込みの失敗と取消。
    private func refreshRestored(
        _ local: ConnectionSessionLocationTrack,
        record: ConnectionSessionLocationTrackSyncRecord,
        accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackAvailability {
        let unverified = ConnectionSessionLocationTrackAvailability.available(local, .restoredEarlier(isVerifiedLatest: false))
        guard let manifest = try await fetchIgnoringFailure({
            try await cloudRepository.remoteManifest(sessionID: record.sessionID, for: accountIdentifier)
        }) else {
            return unverified
        }
        if manifest.manifestDigest == record.manifestDigest {
            return .available(local, .restoredEarlier(isVerifiedLatest: true))
        }
        guard let verified = try await fetchIgnoringFailure({
            try await cloudRepository.download(sessionID: record.sessionID, for: accountIdentifier)
        }) else {
            return unverified
        }
        try syncRepository.replaceWithRestoredTrack(verified, at: now())
        return .available(verified.track, .downloadedNow)
    }

    /// ローカルに無い軌跡を iCloud から取得して復元します。
    ///
    /// 責務: レコードが無ければ何も書かずに `.notInCloud` を、あれば復元して `downloadedNow` を返します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - accountIdentifier: 対象アカウント。
    /// - Returns: 取得した軌跡、または iCloud にも無いこと。
    /// - Throws: 取得と復元の失敗をそのまま投げます(空として返しません)。
    private func downloadMissing(
        _ sessionID: ConnectionSessionID,
        accountIdentifier: String
    ) async throws -> ConnectionSessionLocationTrackAvailability {
        guard let verified = try await cloudRepository.download(sessionID: sessionID, for: accountIdentifier) else {
            return .notInCloud
        }
        try syncRepository.replaceWithRestoredTrack(verified, at: now())
        return .available(verified.track, .downloadedNow)
    }

    /// iCloud からの取得を行い、取消以外の失敗を「取得できなかった」として扱います。
    ///
    /// 責務: 照合のための取得の失敗を nil へまとめ、取消だけを投げ直します。
    /// - Parameter fetch: 取得処理。
    /// - Returns: 取得した値。失敗またはレコード無しなら nil。
    /// - Throws: 取消。
    private func fetchIgnoringFailure<Value>(
        _ fetch: @MainActor () async throws -> Value?
    ) async throws -> Value? {
        do {
            return try await fetch()
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return nil
        }
    }
}
