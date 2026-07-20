import Foundation

/// 接続セッション同期で現在端末が担う役割です。
enum ConnectionSessionSyncDeviceRole: Equatable, Sendable {
    /// Rawログを取得しMac受領証を待つiPhoneです。
    case iPhone
    /// Rawログを取り込み学習元として保持するMacです。
    case macOS
}

/// 終了済みセッションをCloudKitへ送り、Mac取込受領証を反映します。
@MainActor
struct SynchronizeConnectionSessionsUseCase {
    /// 接続履歴のローカル保存先です。
    private let sessionRepository: any ConnectionSessionRepository
    /// Rawログと端末別保管状態のローカル保存先です。
    private let rawLogRepository: any ConnectionSessionRawLogRepository
    /// 削除マーカーを現在端末へ反映するセッション物理削除境界です。
    private let sessionErasureRepository: any ConnectionSessionErasureRepository
    /// CloudKitのセッション転送境界です。
    private let transferRepository: any ConnectionSessionTransferRepository
    /// 現在端末が担う同期役割です。
    private let role: ConnectionSessionSyncDeviceRole
    /// Mac受領証へ記録する現在インストール識別情報です。
    private let installationIdentity: LocalInstallationIdentity?
    /// 受領証日時を生成する注入済みクロックです。
    private let now: () -> Date

    /// ローカル保存先、CloudKit境界、端末役割を固定して生成します。
    ///
    /// 責務: セッションのローカル正本を現在端末のCloudKit同期役割へ結び付けます。
    /// - Parameters:
    ///   - sessionRepository: 接続履歴のローカル保存先。
    ///   - rawLogRepository: Rawログと保管状態のローカル保存先。
    ///   - sessionErasureRepository: 削除マーカーを反映するローカル物理削除境界。
    ///   - transferRepository: CloudKitセッション転送境界。
    ///   - role: iPhone送信元またはMac取込先の役割。
    ///   - installationIdentity: Mac受領証へ使用するインストール識別情報。
    ///   - now: 受領証日時を生成するクロック。
    init(
        sessionRepository: any ConnectionSessionRepository,
        rawLogRepository: any ConnectionSessionRawLogRepository,
        sessionErasureRepository: any ConnectionSessionErasureRepository,
        transferRepository: any ConnectionSessionTransferRepository,
        role: ConnectionSessionSyncDeviceRole,
        installationIdentity: LocalInstallationIdentity? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionRepository = sessionRepository
        self.rawLogRepository = rawLogRepository
        self.sessionErasureRepository = sessionErasureRepository
        self.transferRepository = transferRepository
        self.role = role
        self.installationIdentity = installationIdentity
        self.now = now
    }

    /// 現在アカウントの送信待ちと端末役割別受信処理を実行します。
    ///
    /// 責務: 1件のアカウントスコープを終了済みセッションの双方向同期結果へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: ローカル保存、CloudKit転送、検証、またはMac取込に失敗した場合のエラー。
    func execute(accountIdentifier: String) async throws {
        try await applySessionDeletions(accountIdentifier: accountIdentifier)
        try await uploadPendingSessions(accountIdentifier: accountIdentifier)
        switch role {
        case .iPhone:
            try await applyMacReceipts(accountIdentifier: accountIdentifier)
        case .macOS:
            try await importTransfersOnMac(accountIdentifier: accountIdentifier)
        }
    }

    /// CloudKit削除マーカーを現在端末の物理削除へ反映します。
    ///
    /// 責務: 1件のアカウントに属する全削除マーカーを現在端末のセッション物理削除へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit削除マーカー取得またはローカル物理削除に失敗した場合のエラー。
    private func applySessionDeletions(accountIdentifier: String) async throws {
        let localSessionIDs = Set(try sessionRepository.sessions(for: accountIdentifier).map(\.id))
        let deletedSessionIDs = try await transferRepository.deletedSessionIDs(for: accountIdentifier)
        for sessionID in deletedSessionIDs where localSessionIDs.contains(sessionID) {
            try sessionErasureRepository.deleteSession(sessionID, for: accountIdentifier)
        }
    }

    /// ローカルの終了済み送信待ちセッションをCloudKitへ保存します。
    ///
    /// 責務: 送信可能な全ローカルセッションをCloudKit Assetと保存済みManifestへ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: 履歴読込、Rawログ読込、またはCloudKit保存に失敗した場合のエラー。
    private func uploadPendingSessions(accountIdentifier: String) async throws {
        let sessions = try sessionRepository.sessions(for: accountIdentifier)
        for session in sessions where shouldUpload(session) {
            do {
                let entries = try rawLogRepository.entries(for: session.id)
                let digest = try await transferRepository.upload(
                    ConnectionSessionTransferPackage(session: session, entries: entries),
                    for: accountIdentifier
                )
                try rawLogRepository.markCloudUploaded(sessionID: session.id, manifestDigest: digest)
            } catch {
                try? rawLogRepository.markCloudUploadFailed(sessionID: session.id)
                throw error
            }
        }
    }

    /// セッションが現在CloudKit送信対象かを返します。
    ///
    /// 責務: 1件の接続セッションを終了、Raw保有、転送状態で送信対象判定します。
    /// - Parameter session: 判定する接続セッション。
    /// - Returns: CloudKitへ新規送信または再送する場合は `true`。
    private func shouldUpload(_ session: ConnectionSession) -> Bool {
        session.endedAt != nil
            && session.rawLogSummary.localState == .available
            && session.rawLogSummary.recordCount > 0
            && session.rawLogSummary.cloudState != .uploaded
    }

    /// CloudKit上のMac受領証をiPhone側セッションへ反映します。
    ///
    /// 責務: 受信したMac受領証群を同じManifestのローカルセッションへ関連付けます。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit受領証取得に失敗した場合のエラー。
    private func applyMacReceipts(accountIdentifier: String) async throws {
        let receipts = try await transferRepository.downloadMacReceipts(for: accountIdentifier)
        var appliedSessionIDs = Set<ConnectionSessionID>()
        for (sessionID, receipt) in receipts {
            guard appliedSessionIDs.insert(sessionID).inserted else { continue }
            try? rawLogRepository.markMacImported(receipt, sessionID: sessionID)
        }
    }

    /// CloudKitセッションをMacへ取り込み受領証を発行します。
    ///
    /// 責務: 全検証済み転送をMacローカル正本とCloudKit受領証へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: Mac識別情報不在、CloudKit取得、ローカル取込、または受領証保存に失敗した場合のエラー。
    private func importTransfersOnMac(accountIdentifier: String) async throws {
        guard let installationIdentity else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let transfers = try await transferRepository.downloadTransfers(for: accountIdentifier)
        for transfer in transfers {
            try rawLogRepository.importVerifiedTransfer(transfer)
            let receipt = ConnectionSessionMacImportReceipt(
                deviceID: installationIdentity.id,
                deviceName: installationIdentity.displayName,
                importedAt: now(),
                manifestDigest: transfer.manifestDigest
            )
            try rawLogRepository.markMacImported(receipt, sessionID: transfer.package.session.id)
            try await transferRepository.publishMacReceipt(
                receipt,
                sessionID: transfer.package.session.id,
                for: accountIdentifier
            )
        }
    }
}
