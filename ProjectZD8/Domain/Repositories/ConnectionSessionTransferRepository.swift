/// 接続セッションPayloadとMac受領証をCloudKit経由で交換します。
@MainActor
protocol ConnectionSessionTransferRepository {
    /// Raw Payloadを含まないセッション概要をCloudKitへ保存します。
    ///
    /// 責務: 1件のセッション概要をRaw Assetから独立したCloudKitレコードへ変換します。
    /// - Parameters:
    ///   - metadata: 一覧共有に必要なセッション概要とRaw Manifest。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: 概要の符号化またはCloudKit保存に失敗した場合のエラー。
    func publishMetadata(
        _ metadata: ConnectionSessionCloudMetadata,
        for accountIdentifier: String
    ) async throws

    /// 指定アカウントのセッション概要だけを取得します。
    ///
    /// 責務: CloudKit上の軽量概要レコードをRaw Asset非取得のセッション一覧へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: Raw Payloadを含まないセッション概要。
    /// - Throws: CloudKit取得、復号、または整合性検証に失敗した場合のエラー。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata]

    /// CloudKitに実在するRaw PayloadのManifestを取得します。
    ///
    /// 責務: Raw Assetを読み込まずにセッション別Manifestを復元します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: セッションIDをキーとするRaw Payload Manifest。
    /// - Throws: CloudKit取得または必須フィールド復元に失敗した場合のエラー。
    func downloadTransferManifests(
        for accountIdentifier: String
    ) async throws -> [ConnectionSessionID: String]

    /// 指定セッションのRaw Payloadだけをオンデマンド取得します。
    ///
    /// 責務: 1件のセッションIDをDigest検証済みRaw転送Payloadへ変換します。
    /// - Parameters:
    ///   - sessionID: Raw Payloadを取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: Asset整合性を検証したセッション転送Payload。
    /// - Throws: CloudKit取得、Asset読込、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer

    /// 指定セッションのRaw Payloadを進捗通知付きでオンデマンド取得します。
    ///
    /// 責務: 1件のセッションIDを取得進捗とDigest検証済みRaw転送Payloadへ変換します。
    /// - Parameters:
    ///   - sessionID: Raw Payloadを取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - progress: `0.0...1.0` の範囲で通知するAsset取得進捗。
    /// - Returns: Asset整合性を検証したセッション転送Payload。
    /// - Throws: CloudKit取得、Asset読込、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> VerifiedConnectionSessionTransfer

    /// 終了済みセッションPayloadをCloudKitへ保存します。
    ///
    /// 責務: 1件のセッションPayloadを検証可能なCloudKit Assetへ変換します。
    /// - Parameters:
    ///   - package: 保存するセッションと未デコードRawログ。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 保存したAssetバイトのSHA-256。
    /// - Throws: 符号化、一時ファイル、またはCloudKit保存に失敗した場合のエラー。
    func upload(
        _ package: ConnectionSessionTransferPackage,
        for accountIdentifier: String
    ) async throws -> String

    /// 指定アカウントの検証済みセッションPayloadを取得します。
    ///
    /// 責務: CloudKit上のセッションAsset群をDigest検証済みPayloadへ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: AssetのSHA-256検証に成功したセッションPayload。
    /// - Throws: CloudKit取得、Digest検証、または復号に失敗した場合のエラー。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer]

    /// Macの永続取込受領証をCloudKitへ保存します。
    ///
    /// 責務: 1件のMac取込結果をセッション別CloudKit受領証へ変換します。
    /// - Parameters:
    ///   - receipt: Macが読み戻し検証したManifest受領証。
    ///   - sessionID: 取り込んだ接続セッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Throws: CloudKit保存を完了できない場合のエラー。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws

    /// iPhoneが参照するMac取込受領証を取得します。
    ///
    /// 責務: 指定アカウントのCloudKit受領証をセッションID別の取込結果へ復元します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: セッションIDとMac取込受領証の組。
    /// - Throws: CloudKit取得またはレコード復元に失敗した場合のエラー。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)]

    /// 全端末で物理削除すべきセッションIDを取得します。
    ///
    /// 責務: 1件のアカウントに属するCloudKit削除マーカーをセッションID集合へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 全端末から削除すべき接続セッションID集合。
    /// - Throws: CloudKit取得またはレコード復元に失敗した場合のエラー。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID>

    /// セッション削除マーカーを公開し、対応するCloudKit Payloadと受領証を物理削除します。
    ///
    /// 責務: 1件の接続セッションを全端末削除対象として記録しCloudKit運転データを物理削除します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 削除対象を所有するAppleアカウント識別子。
    /// - Throws: 削除マーカー保存、CloudKit検索、またはレコード削除に失敗した場合のエラー。
    func deleteSession(
        _ sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws

    /// 指定アカウントの全セッション転送とMac受領証を削除します。
    ///
    /// 責務: 1件のアカウント識別子に属するCloudKit運転データを削除済み状態へします。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Throws: CloudKit上のセッションAssetまたはMac受領証を削除できない場合のエラー。
    func deleteAll(for accountIdentifier: String) async throws
}

/// 既存の転送Repository実装へ互換的な軽量同期能力を提供します。
@MainActor
extension ConnectionSessionTransferRepository {
    /// 進捗専用実装を持たない転送先を開始・完了通知付きの既存取得へ委譲します。
    ///
    /// 責務: 既存の単一セッション取得を最小限の進捗通知付き取得へ適合します。
    /// - Parameters:
    ///   - sessionID: Raw Payloadを取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    ///   - progress: 開始時と完了時に通知する取得進捗。
    /// - Returns: Asset整合性を検証したセッション転送Payload。
    /// - Throws: 既存の単一セッション取得に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> VerifiedConnectionSessionTransfer {
        progress(0)
        let transfer = try await downloadTransfer(sessionID: sessionID, for: accountIdentifier)
        progress(1)
        return transfer
    }

    /// 互換実装では既存Payloadが概要も保持するため追加保存を省略します。
    ///
    /// 責務: 既存テスト実装の概要公開要求を副作用なしで受け付けます。
    /// - Parameters:
    ///   - metadata: 既存Payload内に含まれるため使用しない概要。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMetadata(
        _ metadata: ConnectionSessionCloudMetadata,
        for accountIdentifier: String
    ) async throws {}

    /// 既存の全転送取得結果から概要を復元します。
    ///
    /// 責務: 既存Payload配列を互換的なセッション概要配列へ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 既存転送が保持するセッション概要。
    /// - Throws: 既存転送取得に失敗した場合のエラー。
    func downloadMetadata(for accountIdentifier: String) async throws -> [ConnectionSessionCloudMetadata] {
        try await downloadTransfers(for: accountIdentifier).map {
            ConnectionSessionCloudMetadata(session: $0.package.session, manifestDigest: $0.manifestDigest)
        }
    }

    /// 既存の全転送取得結果からManifest辞書を復元します。
    ///
    /// 責務: 既存Payload配列を互換的なセッション別Manifestへ変換します。
    /// - Parameter accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: セッションIDをキーとするManifest。
    /// - Throws: 既存転送取得または重複Manifest検証に失敗した場合のエラー。
    func downloadTransferManifests(
        for accountIdentifier: String
    ) async throws -> [ConnectionSessionID: String] {
        var manifests: [ConnectionSessionID: String] = [:]
        for transfer in try await downloadTransfers(for: accountIdentifier) {
            let id = transfer.package.session.id
            if let existing = manifests[id], existing != transfer.manifestDigest {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            manifests[id] = transfer.manifestDigest
        }
        return manifests
    }

    /// 既存の全転送取得結果から指定セッションを選択します。
    ///
    /// 責務: 既存Payload配列を互換的な単一セッションRaw取得結果へ変換します。
    /// - Parameters:
    ///   - sessionID: 取得するセッションID。
    ///   - accountIdentifier: 同期対象のAppleアカウント識別子。
    /// - Returns: 指定セッションの検証済み転送Payload。
    /// - Throws: 転送不在または既存転送取得に失敗した場合のエラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer {
        guard let transfer = try await downloadTransfers(for: accountIdentifier).first(where: {
            $0.package.session.id == sessionID
        }) else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        return transfer
    }
}
