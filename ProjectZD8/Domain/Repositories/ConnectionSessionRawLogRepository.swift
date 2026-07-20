/// 未デコードOBD応答を接続セッション単位で永続化します。
protocol ConnectionSessionRawLogRepository {
    /// Raw応答を現在セッションの次の順序へ追記します。
    ///
    /// 責務: 1件の未デコードOBD応答を指定セッションへ追加します。
    /// - Parameters:
    ///   - observation: 取得境界が返した未デコード応答。
    ///   - sessionID: 追記対象の接続セッションID。
    /// - Throws: セッション不在、制約違反、または永続化失敗。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws

    /// セッション内のRaw応答を記録順で返します。
    ///
    /// 責務: 1件のセッションIDに属する未デコード応答を順序付きで復元します。
    /// - Parameter sessionID: 読み込む接続セッションID。
    /// - Returns: `sequence`昇順のRawログ。
    /// - Throws: 永続化済みログを読み込めない場合の保存先エラー。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry]

    /// 車両に属する全セッションのRaw応答を時系列で返します。
    ///
    /// 責務: 1件のアカウントと車両IDに属する未デコード応答をセッション境界付きで復元します。
    /// - Parameters:
    ///   - vehicleID: 学習抽出対象の登録車両ID。
    ///   - accountIdentifier: 車両とセッションを所有するAppleアカウント識別子。
    /// - Returns: セッション開始日時、セッションID、`sequence` の安定順で並ぶRawログ。
    /// - Throws: 永続化済みログを読み込めない場合の保存先エラー。
    func entries(
        for vehicleID: VehicleID,
        accountIdentifier: String
    ) throws -> [VehicleConnectionSessionRawLogEntry]

    /// CloudKitへの保存結果をセッションへ記録します。
    ///
    /// 責務: 1件のセッションを指定ManifestでCloudKit保存済みへ遷移させます。
    /// - Parameters:
    ///   - sessionID: 更新する接続セッションID。
    ///   - manifestDigest: 保存済みAssetバイトのSHA-256。
    /// - Throws: セッション更新を完了できない場合の保存先エラー。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws

    /// CloudKit転送失敗を再試行可能状態として記録します。
    ///
    /// 責務: 1件のセッションをCloudKit転送失敗状態へ遷移させます。
    /// - Parameter sessionID: 更新する接続セッションID。
    /// - Throws: セッション更新を完了できない場合の保存先エラー。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws

    /// Mac取込受領証をセッションへ保存します。
    ///
    /// 責務: 1件のMac受領証を対応するセッションManifestへ関連付けます。
    /// - Parameters:
    ///   - receipt: Macが発行した永続取込受領証。
    ///   - sessionID: 更新する接続セッションID。
    /// - Throws: セッション更新を完了できない場合の保存先エラー。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws

    /// 検証済み転送Payloadを現在端末へ冪等に取り込みます。
    ///
    /// 責務: 1件の検証済みセッションPayloadをローカル接続履歴とRawログへ復元します。
    /// - Parameter transfer: CloudKitから取得した検証済み転送Payload。
    /// - Throws: 既存内容との不一致、制約違反、または永続化失敗。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws

    /// セッション概要を残して現在端末のRaw応答だけを除去します。
    ///
    /// 責務: 1件の終了済みセッションから端末内RawログPayloadだけを削除します。
    /// - Parameter sessionID: ローカルPayloadを除去するセッションID。
    /// - Throws: セッション状態不正または永続化失敗。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws
}
