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

    /// セッション内のRaw応答件数を返します。
    ///
    /// 責務: 1件のセッションIDに属するRawログ総件数を復元します。
    /// - Parameter sessionID: 件数を取得する接続セッションID。
    /// - Returns: 保存済みRawログ件数。
    /// - Throws: 永続化済みログ件数を読み込めない場合の保存先エラー。
    func entryCount(for sessionID: ConnectionSessionID) throws -> Int

    /// セッション内のRaw応答を指定順序より後から上限件数まで返します。
    ///
    /// 責務: 1件のセッションRawログを記録順カーソルで分割して復元します。
    /// - Parameters:
    ///   - sessionID: 読み込む接続セッションID。
    ///   - sequence: 直前に読み込んだ記録順序。先頭ページでは `nil`。
    ///   - limit: 1回で返す最大件数。
    /// - Returns: `sequence`昇順で指定上限以下のRawログ。
    /// - Throws: 永続化済みログを読み込めない場合の保存先エラー。
    func entries(
        for sessionID: ConnectionSessionID,
        after sequence: Int64?,
        limit: Int
    ) throws -> [ConnectionSessionRawLogEntry]

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

/// ページ読取を専用実装しないリポジトリへ互換動作を提供します。
extension ConnectionSessionRawLogRepository {
    /// 全件読取結果からRawログ件数を返します。
    ///
    /// 責務: 既存の全件読取能力をRawログ件数へ変換します。
    /// - Parameter sessionID: 件数を取得する接続セッションID。
    /// - Returns: 保存済みRawログ件数。
    /// - Throws: 全件読取に失敗した場合の保存先エラー。
    func entryCount(for sessionID: ConnectionSessionID) throws -> Int {
        try entries(for: sessionID).count
    }

    /// 全件読取結果へ記録順カーソルと上限を適用します。
    ///
    /// 責務: 既存の全件読取能力を互換的な1ページのRawログへ変換します。
    /// - Parameters:
    ///   - sessionID: 読み込む接続セッションID。
    ///   - sequence: 直前に読み込んだ記録順序。先頭ページでは `nil`。
    ///   - limit: 1回で返す最大件数。
    /// - Returns: `sequence`昇順で指定上限以下のRawログ。
    /// - Throws: 全件読取に失敗した場合の保存先エラー。
    func entries(
        for sessionID: ConnectionSessionID,
        after sequence: Int64?,
        limit: Int
    ) throws -> [ConnectionSessionRawLogEntry] {
        let lowerBound = sequence ?? -1
        return Array(
            try entries(for: sessionID)
                .sorted { $0.sequence < $1.sequence }
                .lazy
                .filter { $0.sequence > lowerBound }
                .prefix(max(0, limit))
        )
    }
}
