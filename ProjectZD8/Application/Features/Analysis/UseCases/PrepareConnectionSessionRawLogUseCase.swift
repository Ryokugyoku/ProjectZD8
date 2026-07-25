import Foundation

/// セッション解析前にRawログをローカルで利用可能にします。
@MainActor
struct PrepareConnectionSessionRawLogUseCase {
    /// 解析対象セッションの最新ローカル状態を取得する保存先です。
    private let sessionRepository: any ConnectionSessionRepository
    /// Rawログのローカル保存先です。
    private let rawLogRepository: any ConnectionSessionRawLogRepository
    /// CloudKitのオンデマンド転送境界です。
    private let transferRepository: any ConnectionSessionTransferRepository
    /// 最終閲覧日時を生成するクロックです。
    private let now: () -> Date

    /// セッション保存先、Raw保存先、CloudKit境界、クロックを固定して生成します。
    ///
    /// 責務: 解析対象セッションをRawログ利用可能状態へする依存関係を固定します。
    /// - Parameters:
    ///   - sessionRepository: 解析対象セッションの最新ローカル状態を取得する保存先。
    ///   - rawLogRepository: Rawログのローカル保存先。
    ///   - transferRepository: CloudKitのオンデマンド転送境界。
    ///   - now: 最終閲覧日時を生成するクロック。
    init(
        sessionRepository: any ConnectionSessionRepository,
        rawLogRepository: any ConnectionSessionRawLogRepository,
        transferRepository: any ConnectionSessionTransferRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionRepository = sessionRepository
        self.rawLogRepository = rawLogRepository
        self.transferRepository = transferRepository
        self.now = now
    }

    /// 指定セッションのRawログを必要時だけCloudKitから復元します。
    ///
    /// 責務: 1件の解析対象セッションをオンデマンド取得と最終閲覧記録へ変換します。
    /// - Parameters:
    ///   - session: 解析対象の接続セッション概要。
    ///   - downloadProgress: CloudKit取得時に `0.0...1.0` で通知する進捗。
    /// - Throws: CloudKit取得、整合性検証、ローカル復元、または閲覧日時保存に失敗した場合のエラー。
    func execute(
        session: ConnectionSession,
        downloadProgress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws {
        guard let currentSession = try sessionRepository
            .sessions(for: session.accountIdentifier)
            .first(where: { $0.id == session.id }) else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        if currentSession.rawLogSummary.localState == .removed {
            let transfer = try await transferRepository.downloadTransfer(
                sessionID: currentSession.id,
                for: currentSession.accountIdentifier,
                progress: downloadProgress
            )
            guard transfer.package.session.id == currentSession.id,
                  transfer.package.session.accountIdentifier == currentSession.accountIdentifier,
                  transfer.manifestDigest == currentSession.rawLogSummary.manifestDigest else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            try rawLogRepository.restoreVerifiedTransfer(transfer)
        }
        try rawLogRepository.markRawLogAccessed(at: now(), sessionID: currentSession.id)
    }
}
