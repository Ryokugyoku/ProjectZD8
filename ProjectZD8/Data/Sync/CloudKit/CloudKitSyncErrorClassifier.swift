import CloudKit

/// CloudKitのエラーを、利用者へ見せる失敗と、レコード保存失敗時の対処へ分類します。
nonisolated struct CloudKitSyncErrorClassifier: Sendable {
    /// レコード保存に失敗した時の対処です。
    nonisolated enum SaveFailureHandling: Equatable, Sendable {
        /// サーバー側が更新されていた。サーバーの版と後勝ちで解決する。
        case resolveConflict
        /// ゾーンが無い。ゾーンを作り直し、システムフィールドを捨てて再送する。
        case recreateZone
        /// サーバーにレコードが無い。システムフィールドを捨てて新規として再送する。
        case recreateRecord
        /// 順序や資産の一時的な問題。そのまま再送する。
        case retry
        /// 同期エンジンが自動で再試行する一時的な失敗。
        case automaticRetry
        /// 再送しても解決しない失敗。状態として表示する。
        case report(CloudSyncFailure)
    }

    /// 責務: 分類器を生成します。
    init() {}

    /// 責務: 任意のエラーを利用者へ見せる同期の失敗へ変換します。
    func failure(for error: any Error) -> CloudSyncFailure {
        if let failure = error as? CloudSyncFailure { return failure }
        if error is SessionArchiveCodecError { return .integrity }
        if let storeError = error as? SyncLocalStoreError, storeError == .rowNotFound { return .notFound }
        guard let ckError = error as? CKError else { return .other }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .network
        case .quotaExceeded:
            return .quotaExceeded
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return .notFound
        default:
            return .other
        }
    }

    /// 責務: アーカイブレコードの削除の失敗が「既にサーバーに無い」(削除済みと同じ)かどうかを返します。
    func isAlreadyGone(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone: return true
        default: return false
        }
    }

    /// 責務: レコード保存の失敗に対する対処を決めます。
    func handling(forSaveError error: CKError) -> SaveFailureHandling {
        switch error.code {
        case .serverRecordChanged:
            return .resolveConflict
        case .zoneNotFound, .userDeletedZone:
            return .recreateZone
        case .unknownItem:
            return .recreateRecord
        case .referenceViolation, .batchRequestFailed, .assetFileNotFound, .assetFileModified:
            return .retry
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled:
            return .automaticRetry
        case .quotaExceeded:
            return .report(.quotaExceeded)
        default:
            return .report(.other)
        }
    }
}
