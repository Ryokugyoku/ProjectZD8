import Foundation

/// 製品用セッションDBを準備できない場合に明示的失敗を返します。
struct UnavailableConnectionSessionRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository, ConnectionSessionErasureRepository, AccountConnectionSessionErasureRepository, ConnectionSessionAcquisitionRepository, ConnectionSessionAcquisitionBatchRepository, ConnectionSessionAcquisitionTerminationRepository {
    /// manifest開始保存を利用不能として失敗させます。
    ///
    /// 責務: 取得開始要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - manifest: 保存できないmanifest。
    ///   - startedAt: 保存できない開始日時。
    ///   - sessionID: 保存できない親session。
    /// - Throws: 常に `.unavailable`。
    func saveStartOnce(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// 取得終了保存を利用不能として失敗させます。
    ///
    /// 責務: 取得終了要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - endedAt: 保存できない終了日時。
    ///   - reason: 保存できない終了理由。
    ///   - sessionID: 保存できない親session。
    /// - Throws: 常に `.unavailable`。
    func appendEnd(at endedAt: Date, reason: ConnectionSessionEndReason, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// manifest読取を利用不能として失敗させます。
    ///
    /// 責務: manifest照会を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 読み込めないsession。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// 取得境界読取を利用不能として失敗させます。
    ///
    /// 責務: 取得境界照会を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 読み込めないsession。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence] {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// batch開始保存を利用不能として失敗させます。
    ///
    /// 責務: batch開始要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - evidence: 保存できないbatch証拠。
    ///   - sessionID: 保存できない親session。
    /// - Throws: 常に `.unavailable`。
    func beginBatch(_ evidence: AcquisitionBatchEvidence, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// dispatch開始保存を利用不能として失敗させます。
    ///
    /// 責務: dispatch開始要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - requestOrdinal: 保存できない要求順。
    ///   - batchIdentity: 保存できないbatch identity。
    ///   - sessionID: 保存できない親session。
    /// - Throws: 常に `.unavailable`。
    func markRequestDispatchBegun(requestOrdinal: Int, in batchIdentity: AcquisitionBatchIdentity, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// responded保存を利用不能として失敗させます。
    ///
    /// 責務: responded Raw保存要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - observation: 保存できないRaw観測。
    ///   - valueOutcome: 保存できない値評価結果。
    ///   - elapsedNanoseconds: 保存できない経過時間。
    ///   - reasonCode: 保存できない任意の理由code。
    ///   - requestOrdinal: 保存できない要求順。
    ///   - batchIdentity: 保存できないbatch identity。
    ///   - sessionID: 保存できない親session。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func saveRespondedRequest(
        observation: OBDRawResponseObservation,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// nonresponded保存を利用不能として失敗させます。
    ///
    /// 責務: nonresponded保存要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - outcome: 保存できない非応答結果。
    ///   - elapsedNanoseconds: 保存できない任意の経過時間。
    ///   - reasonCode: 保存できない任意の理由code。
    ///   - requestOrdinal: 保存できない要求順。
    ///   - batchIdentity: 保存できないbatch identity。
    ///   - sessionID: 保存できない親session。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func saveNonRespondedRequest(
        outcome: PIDRequestTransportOutcome,
        elapsedNanoseconds: UInt64?,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// batch終端保存を利用不能として失敗させます。
    ///
    /// 責務: batch終端要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - evidence: 保存できないterminal batch。
    ///   - sessionID: 保存できない親session。
    /// - Throws: 常に `.unavailable`。
    func finishBatch(_ evidence: AcquisitionBatchEvidence, for sessionID: ConnectionSessionID) throws {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// batch読取を利用不能として失敗させます。
    ///
    /// 責務: batch照会を明示的な保存先利用不能へ変換します。
    /// - Parameter sessionID: 読み込めないsession。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func batches(for sessionID: ConnectionSessionID) throws -> [AcquisitionBatchEvidence] {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// session取得終了を利用不能として失敗させます。
    ///
    /// 責務: 原子的なsession取得終了要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - session: 終了保存できない親session。
    ///   - endedAt: 保存できない終了日時。
    ///   - reason: 保存できない終了理由。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func finishSessionAcquisition(
        _ session: ConnectionSession,
        endedAt: Date,
        reason: ConnectionSessionEndReason
    ) throws -> ConnectionSession {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }

    /// 中断session回復を利用不能として失敗させます。
    ///
    /// 責務: process終了回復要求を明示的な保存先利用不能へ変換します。
    /// - Parameters:
    ///   - accountIdentifier: 回復照会できないアカウント識別子。
    ///   - recoveredAt: 回復保存できない日時。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `.unavailable`。
    func recoverInterruptedSessionAcquisitions(
        for accountIdentifier: String,
        recoveredAt: Date
    ) throws -> [ConnectionSession] {
        throw ConnectionSessionAcquisitionRepositoryError.unavailable
    }
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
