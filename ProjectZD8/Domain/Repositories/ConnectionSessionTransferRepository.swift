/// 接続セッションPayloadとMac受領証をCloudKit経由で交換します。
@MainActor
protocol ConnectionSessionTransferRepository {
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
