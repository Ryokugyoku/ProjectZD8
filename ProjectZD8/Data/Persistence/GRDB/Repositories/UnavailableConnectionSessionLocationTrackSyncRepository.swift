import Foundation

/// 走行ルートの同期記録の保存先DBを準備できない場合に明示的失敗を返します。
nonisolated struct UnavailableConnectionSessionLocationTrackSyncRepository: ConnectionSessionLocationTrackSyncRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 候補の読取を利用不能エラーへ変換し、空データとして扱いません。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func uploadCandidates(for accountIdentifier: String) throws -> [ConnectionSessionLocationTrackUploadCandidate] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 軌跡の読取を利用不能エラーへ変換し、空の軌跡として扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func track(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrack {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 同期記録の読取を利用不能エラーへ変換し、記録なしとして扱いません。
    /// - Parameter sessionID: 使用しないセッション。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func syncRecord(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrackSyncRecord? {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 送信済みの記録を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - sessionID: 使用しないセッション。
    ///   - manifestDigest: 使用しないdigest。
    ///   - watermark: 使用しない水位。
    ///   - date: 使用しない時刻。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func markUploaded(
        sessionID: ConnectionSessionID,
        manifestDigest: String,
        watermark: ConnectionSessionLocationTrackWatermark,
        at date: Date
    ) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 復元を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameters:
    ///   - verified: 使用しない軌跡。
    ///   - date: 使用しない時刻。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func replaceWithRestoredTrack(_ verified: VerifiedConnectionSessionLocationTrack, at date: Date) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }
}
