import Foundation

/// 接続セッション同期で現在端末が担う役割です。
enum ConnectionSessionSyncDeviceRole: Equatable, Sendable {
    /// セッション概要を送受信し既存Mac受領証を表示するiPhoneです。
    case iPhone
    /// セッション概要をiPhoneと同じ規則で送受信するMacです。
    case macOS
}

/// 終了済みセッション概要を双方向同期し、Raw PayloadをCloudKitへ保管します。
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
    /// ローカル保存先、CloudKit境界、端末役割を固定して生成します。
    ///
    /// 責務: セッションのローカル正本を現在端末のCloudKit同期役割へ結び付けます。
    /// - Parameters:
    ///   - sessionRepository: 接続履歴のローカル保存先。
    ///   - rawLogRepository: Rawログと保管状態のローカル保存先。
    ///   - sessionErasureRepository: 削除マーカーを反映するローカル物理削除境界。
    ///   - transferRepository: CloudKitセッション転送境界。
    ///   - role: 既存受領証を反映するiPhoneまたは対等同期するMacの役割。
    init(
        sessionRepository: any ConnectionSessionRepository,
        rawLogRepository: any ConnectionSessionRawLogRepository,
        sessionErasureRepository: any ConnectionSessionErasureRepository,
        transferRepository: any ConnectionSessionTransferRepository,
        role: ConnectionSessionSyncDeviceRole
    ) {
        self.sessionRepository = sessionRepository
        self.rawLogRepository = rawLogRepository
        self.sessionErasureRepository = sessionErasureRepository
        self.transferRepository = transferRepository
        self.role = role
    }

    /// 現在アカウントの送信待ちと端末役割別受信処理を実行します。
    ///
    /// 責務: 1件のアカウントスコープを終了済みセッションの双方向同期結果へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: ローカル保存、CloudKit概要・Raw転送、または整合性検証に失敗した場合のエラー。
    func execute(accountIdentifier: String) async throws {
        try await applySessionDeletions(accountIdentifier: accountIdentifier)
        let remoteMetadata = try await transferRepository.downloadMetadata(for: accountIdentifier)
        let remoteManifestDigests = try await transferRepository.downloadTransferManifests(
            for: accountIdentifier
        )
        let uploadedTransfers = try await uploadPendingSessions(
            accountIdentifier: accountIdentifier,
            remoteManifestDigests: remoteManifestDigests
        )
        let currentManifestDigests = remoteManifestDigests.merging(
            uploadedTransfers.reduce(into: [:]) { output, transfer in
                output[transfer.package.session.id] = transfer.manifestDigest
            },
            uniquingKeysWith: { _, uploaded in uploaded }
        )
        try await publishLocalMetadata(
            accountIdentifier: accountIdentifier,
            remoteManifestDigests: currentManifestDigests,
            existingRemoteSessionIDs: Set(remoteMetadata.map(\.session.id))
        )
        let uploadedMetadata = uploadedTransfers.map {
            ConnectionSessionCloudMetadata(
                session: metadataSession($0.package.session, manifestDigest: $0.manifestDigest),
                manifestDigest: $0.manifestDigest
            )
        }
        try importMetadata(
            metadataByReplacingRemoteWithUploads(remoteMetadata, uploads: uploadedMetadata)
        )
        if role == .iPhone {
            try await applyMacReceipts(accountIdentifier: accountIdentifier)
        }
    }

    /// CloudKit上にRaw Payloadが実在するローカルセッション概要を公開します。
    ///
    /// 責務: 全ローカル終了済みセッションをRaw Asset非依存のCloudKit概要へ変換します。
    /// - Parameters:
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - remoteManifestDigests: CloudKitに実在するセッション別Raw Manifest。
    ///   - existingRemoteSessionIDs: 同期開始時点ですでに概要が存在するセッションID。
    /// - Throws: 履歴取得、Manifest整合性検証、または概要保存に失敗した場合のエラー。
    private func publishLocalMetadata(
        accountIdentifier: String,
        remoteManifestDigests: [ConnectionSessionID: String],
        existingRemoteSessionIDs: Set<ConnectionSessionID>
    ) async throws {
        for session in try sessionRepository.sessions(for: accountIdentifier)
        where session.endedAt != nil && !existingRemoteSessionIDs.contains(session.id) {
            guard let remoteDigest = remoteManifestDigests[session.id] else { continue }
            if let localDigest = session.rawLogSummary.manifestDigest,
               session.rawLogSummary.cloudState == .uploaded,
               localDigest != remoteDigest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            try await transferRepository.publishMetadata(
                ConnectionSessionCloudMetadata(
                    session: metadataSession(session, manifestDigest: remoteDigest),
                    manifestDigest: remoteDigest
                ),
                for: accountIdentifier
            )
        }
    }

    /// 端末固有状態を除いたセッション概要を生成します。
    ///
    /// 責務: 1件のローカルセッションを一覧同期用の安定した概要表現へ正規化します。
    /// - Parameters:
    ///   - session: 正規化する終了済みセッション。
    ///   - manifestDigest: CloudKitに実在するRaw Payload Manifest。
    /// - Returns: 件数と容量を保持し端末固有状態を除いたセッション。
    private func metadataSession(
        _ session: ConnectionSession,
        manifestDigest: String
    ) -> ConnectionSession {
        var metadata = session
        metadata.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: session.rawLogSummary.recordCount,
            byteCount: session.rawLogSummary.byteCount,
            localState: session.rawLogSummary.recordCount == 0 ? .empty : .removed,
            cloudState: .uploaded,
            manifestDigest: manifestDigest,
            macImportReceipt: nil,
            lastAccessedAt: nil
        )
        return metadata
    }

    /// 今回公開した概要で同期開始時の古い概要を置き換えます。
    ///
    /// 責務: リモート概要と今回のアップロード概要をセッションID別の最新概要へ統合します。
    /// - Parameters:
    ///   - remoteMetadata: 同期開始時にCloudKitから取得した概要群。
    ///   - uploads: 今回Raw Payloadを公開したセッション概要群。
    /// - Returns: 同一セッションでは今回の概要だけを保持する取込対象群。
    private func metadataByReplacingRemoteWithUploads(
        _ remoteMetadata: [ConnectionSessionCloudMetadata],
        uploads: [ConnectionSessionCloudMetadata]
    ) -> [ConnectionSessionCloudMetadata] {
        let uploadedSessionIDs = Set(uploads.map(\.session.id))
        return remoteMetadata.filter { !uploadedSessionIDs.contains($0.session.id) } + uploads
    }

    /// CloudKit概要群をローカル一覧へ取り込みます。
    ///
    /// 責務: 全セッション概要をRaw Payload非取得のローカル履歴へ変換します。
    /// - Parameter metadata: CloudKitから取得したRaw非包含セッション概要群。
    /// - Throws: 重複Manifest競合またはローカル概要取込に失敗した場合のエラー。
    private func importMetadata(_ metadata: [ConnectionSessionCloudMetadata]) throws {
        var manifests: [ConnectionSessionID: String] = [:]
        for item in metadata {
            let sessionID = item.session.id
            if let existing = manifests[sessionID], existing != item.manifestDigest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            manifests[sessionID] = item.manifestDigest
            try rawLogRepository.importCloudMetadata(item)
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
}
