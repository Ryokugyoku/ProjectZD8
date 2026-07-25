import Foundation

/// 製品用セッションDBを準備できない場合に明示的失敗を返します。
struct UnavailableConnectionSessionRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository, ConnectionSessionErasureRepository, AccountConnectionSessionErasureRepository {
    /// 保存先利用不能を返します。
    ///
    /// 責務: セッション保存要求を利用不能エラーとして失敗させます。
    /// - Parameter session: 保存できない接続セッション。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func save(_ session: ConnectionSession) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 保存先利用不能を返します。
    ///
    /// 責務: セッション取得要求を利用不能エラーとして失敗させます。
    /// - Parameter accountIdentifier: 取得できないAppleアカウント識別子。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// アカウント単位の運転データ削除を利用不能として失敗させます。
    ///
    /// 責務: 1件のアカウント削除要求を明示的な保存先利用不能へ変換します。
    /// - Parameter accountIdentifier: 削除できないAppleアカウント識別子。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func deleteSessions(for accountIdentifier: String) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// セッション単位の物理削除を利用不能として失敗させます。
    ///
    /// 責務: 1件のセッション物理削除要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - sessionID: 削除できないセッションID。
    ///   - accountIdentifier: 利用不能な保存先のAppleアカウント識別子。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func deleteSession(
        _ sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// Raw応答保存要求を利用不能として失敗させます。
    ///
    /// 責務: 1件のRaw応答追記を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - observation: 保存できない未デコード応答。
    ///   - sessionID: 利用不能な保存先のセッションID。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// Rawログ読込要求を利用不能として失敗させます。
    ///
    /// 責務: 1件のRawログ照会を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 読み込めないセッションID。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 車両別Rawログ読込要求を利用不能として失敗させます。
    ///
    /// 責務: 1件の車両別Rawログ照会を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - vehicleID: 読み込めない登録車両ID。
    ///   - accountIdentifier: 読み込めないAppleアカウント識別子。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func entries(
        for vehicleID: VehicleID,
        accountIdentifier: String
    ) throws -> [VehicleConnectionSessionRawLogEntry] {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// CloudKit保存済み更新を利用不能として失敗させます。
    ///
    /// 責務: 1件のCloudKit保存結果を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - sessionID: 更新できないセッションID。
    ///   - manifestDigest: 保存できないManifest SHA-256。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// CloudKit失敗状態の更新を利用不能として失敗させます。
    ///
    /// 責務: 1件のCloudKit失敗状態を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 更新できないセッションID。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// Mac受領証保存を利用不能として失敗させます。
    ///
    /// 責務: 1件のMac受領証を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - receipt: 保存できないMac受領証。
    ///   - sessionID: 更新できないセッションID。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// 検証済み転送の取込を利用不能として失敗させます。
    ///
    /// 責務: 1件の検証済み転送を明示的な保存先利用不能へ変換します。
    /// - Parameter transfer: 取り込めない検証済み転送Payload。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// セッション概要取込を利用不能として失敗させます。
    ///
    /// 責務: 1件のCloudKit概要取込要求を明示的な保存先利用不能へ変換します。
    /// - Parameter metadata: 取り込めないセッション概要。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func importCloudMetadata(_ metadata: ConnectionSessionCloudMetadata) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// オンデマンドRaw復元を利用不能として失敗させます。
    ///
    /// 責務: 1件の検証済みRaw復元要求を明示的な保存先利用不能へ変換します。
    /// - Parameter transfer: 復元できない転送Payload。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func restoreVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// Raw最終閲覧日時更新を利用不能として失敗させます。
    ///
    /// 責務: 1件のRaw閲覧記録要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - date: 保存できない閲覧日時。
    ///   - sessionID: 更新できないセッションID。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func markRawLogAccessed(at date: Date, sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }

    /// ローカルRawログ除去を利用不能として失敗させます。
    ///
    /// 責務: 1件のローカル除去要求を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 除去できないセッションID。
    /// - Throws: 常に `ConnectionSessionRepositoryError.unavailable`。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionRepositoryError.unavailable
    }
}
