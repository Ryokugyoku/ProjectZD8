import Foundation

/// 接続セッション同期で現在端末が担う役割です。
enum ConnectionSessionSyncDeviceRole: Equatable, Sendable {
    /// セッションを送受信しMac受領証を表示するiPhoneです。
    case iPhone
    /// セッションを送受信し取込受領証を発行するMacです。
    case macOS
}

/// 終了済みセッションをCloudKit経由で双方向同期し、Mac取込受領証を反映します。
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
        let remoteTransfers = try await transferRepository.downloadTransfers(for: accountIdentifier)
        let remoteManifestDigests = try manifestDigestsBySessionID(remoteTransfers)
        let uploadedTransfers = try await uploadPendingSessions(
            accountIdentifier: accountIdentifier,
            remoteManifestDigests: remoteManifestDigests
        )
        let transfersToImport = transfersByReplacingRemoteWithUploads(
            remoteTransfers,
            uploads: uploadedTransfers
        )
        try await importTransfers(transfersToImport, accountIdentifier: accountIdentifier)
        if role == .iPhone {
            try await applyMacReceipts(accountIdentifier: accountIdentifier)
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
    /// - Parameters:
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - remoteManifestDigests: CloudKitで実在確認できたセッション別Manifest。
    /// - Returns: 今回CloudKitへ保存した検証可能な転送Payload。
    /// - Throws: 履歴読込、Rawログ読込、またはCloudKit保存に失敗した場合のエラー。
    private func uploadPendingSessions(
        accountIdentifier: String,
        remoteManifestDigests: [ConnectionSessionID: String]
    ) async throws -> [VerifiedConnectionSessionTransfer] {
        let sessions = try sessionRepository.sessions(for: accountIdentifier)
        var uploadedTransfers: [VerifiedConnectionSessionTransfer] = []
        for session in sessions where try shouldUpload(
            session,
            remoteManifestDigest: remoteManifestDigests[session.id]
        ) {
            do {
                let entries = try rawLogRepository.entries(for: session.id)
                let package = ConnectionSessionTransferPackage(
                    session: sessionForTransfer(session, entries: entries),
                    entries: entries
                )
                let digest = try await transferRepository.upload(
                    package,
                    for: accountIdentifier
                )
                try rawLogRepository.markCloudUploaded(sessionID: session.id, manifestDigest: digest)
                uploadedTransfers.append(
                    VerifiedConnectionSessionTransfer(package: package, manifestDigest: digest)
                )
            } catch {
                try? rawLogRepository.markCloudUploadFailed(sessionID: session.id)
                throw error
            }
        }
        return uploadedTransfers
    }

    /// 今回再公開したセッションについて取得時点の古い転送を置き換えます。
    ///
    /// 責務: リモート取得結果と同一実行内の再公開結果をセッションIDごとの最新転送へ統合します。
    /// - Parameters:
    ///   - remoteTransfers: 同期開始時にCloudKitから取得した転送群。
    ///   - uploads: 現在端末が今回CloudKitへ再公開した転送群。
    /// - Returns: 再公開したセッションでは今回の転送だけを保持する取込対象群。
    private func transfersByReplacingRemoteWithUploads(
        _ remoteTransfers: [VerifiedConnectionSessionTransfer],
        uploads: [VerifiedConnectionSessionTransfer]
    ) -> [VerifiedConnectionSessionTransfer] {
        let uploadedSessionIDs = Set(uploads.map(\.package.session.id))
        return remoteTransfers.filter { !uploadedSessionIDs.contains($0.package.session.id) } + uploads
    }

    /// 端末固有の同期証跡を除いたセッション転送表現を生成します。
    ///
    /// 責務: 1件のローカルセッションとRawログを再送しても変化しない転送用セッションへ正規化します。
    /// - Parameters:
    ///   - session: 転送する終了済みセッション。
    ///   - entries: 転送する未デコードRawログ。
    /// - Returns: Raw件数を保持し、端末別CloudKit状態と受領証を除いたセッション。
    private func sessionForTransfer(
        _ session: ConnectionSession,
        entries: [ConnectionSessionRawLogEntry]
    ) -> ConnectionSession {
        var transferable = session
        transferable.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: Int64(entries.count),
            byteCount: entries.reduce(0) { $0 + Int64($1.payload.count) },
            localState: entries.isEmpty ? .empty : .available,
            cloudState: .notUploaded,
            manifestDigest: nil,
            macImportReceipt: nil
        )
        return transferable
    }

    /// セッション履歴が現在CloudKit送信対象かを返します。
    ///
    /// 責務: 1件の接続セッションを終了、ローカル除去、CloudKit実在状態で送信対象判定します。
    /// - Parameters:
    ///   - session: 判定する接続セッション。
    ///   - remoteManifestDigest: CloudKitで実在確認できたManifest。
    /// - Returns: CloudKitへ新規送信または再送する場合は `true`。
    /// - Throws: 同じセッションIDでローカルとCloudKitのManifestが競合する場合のエラー。
    private func shouldUpload(
        _ session: ConnectionSession,
        remoteManifestDigest: String?
    ) throws -> Bool {
        guard session.endedAt != nil,
              session.rawLogSummary.localState != .removed else { return false }
        if let remoteManifestDigest {
            if session.rawLogSummary.cloudState == .pending
                || session.rawLogSummary.cloudState == .failed {
                return true
            }
            if let localManifestDigest = session.rawLogSummary.manifestDigest,
               localManifestDigest != remoteManifestDigest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            return false
        }
        return true
    }

    /// CloudKit転送群をセッション別Manifest辞書へ変換します。
    ///
    /// 責務: 全検証済み転送を重複競合のないセッションID別Manifestへ変換します。
    /// - Parameter transfers: CloudKitから取得した検証済み転送群。
    /// - Returns: セッションIDをキーとするManifest辞書。
    /// - Throws: 同じセッションIDに異なるManifestが含まれる場合のエラー。
    private func manifestDigestsBySessionID(
        _ transfers: [VerifiedConnectionSessionTransfer]
    ) throws -> [ConnectionSessionID: String] {
        var output: [ConnectionSessionID: String] = [:]
        for transfer in transfers {
            let sessionID = transfer.package.session.id
            if let existing = output[sessionID], existing != transfer.manifestDigest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            output[sessionID] = transfer.manifestDigest
        }
        return output
    }

    /// CloudKit上のMac受領証をiPhone側セッションへ反映します。
    ///
    /// 責務: 受信したMac受領証群を同じManifestのローカルセッションへ関連付けます。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit受領証取得に失敗した場合のエラー。
    private func applyMacReceipts(accountIdentifier: String) async throws {
        let receipts = try await transferRepository.downloadMacReceipts(for: accountIdentifier)
        let localSessionIDs = Set(try sessionRepository.sessions(for: accountIdentifier).map(\.id))
        var appliedSessionIDs = Set<ConnectionSessionID>()
        for (sessionID, receipt) in receipts where localSessionIDs.contains(sessionID) {
            guard appliedSessionIDs.insert(sessionID).inserted else { continue }
            try rawLogRepository.markMacImported(receipt, sessionID: sessionID)
        }
    }

    /// CloudKitセッションを現在端末へ取り込み、Macでは受領証を発行します。
    ///
    /// 責務: 全検証済み転送を端末ローカル正本と役割に応じたMac受領証へ変換します。
    /// - Parameters:
    ///   - transfers: ローカルへ取り込む検証済み転送群。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit取得、ローカル取込、Mac識別情報不在、または受領証保存に失敗した場合のエラー。
    private func importTransfers(
        _ transfers: [VerifiedConnectionSessionTransfer],
        accountIdentifier: String
    ) async throws {
        for transfer in transfers {
            try rawLogRepository.importVerifiedTransfer(transfer)
            guard role == .macOS else { continue }
            guard let installationIdentity else {
                throw ConnectionSessionRepositoryError.invalidState
            }
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
