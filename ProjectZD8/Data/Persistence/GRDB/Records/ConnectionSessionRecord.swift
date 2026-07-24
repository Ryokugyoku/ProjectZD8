import Foundation
import GRDB

/// GRDBへ保存する接続セッションの永続化表現です。
struct ConnectionSessionRecord: Codable, FetchableRecord, PersistableRecord {
    /// 接続セッションテーブル名です。
    static let databaseTableName = "connection_sessions"

    /// セッションUUIDの文字列表現です。
    let id: String
    /// Appleアカウント識別子です。
    let accountIdentifier: String
    /// 開始日時です。
    let startedAt: Date
    /// 終了日時です。
    let endedAt: Date?
    /// 終了原因の安定文字列表現です。
    let endReason: String?
    /// ユーザーが確認した停止種別の安定文字列表現です。
    let stopReviewDecision: String?
    /// 関連付けた登録車両UUIDの文字列表現です。
    let vehicleID: String?
    /// 接続時点の車両名称です。
    let vehicleName: String?
    /// 接続時点の車両代表識別値です。
    let vehicleDisplayIdentifier: String?
    /// ログ取得元Appleプラットフォームの安定文字列表現です。
    let acquisitionPlatform: String?
    /// ログ取得時のユーザー向け端末名です。
    let acquisitionDeviceName: String?
    /// セッション内で最初に取得した累積走行距離です。
    let startingOdometerKilometers: Double?
    /// セッション内で最後に取得した累積走行距離です。
    let endingOdometerKilometers: Double?
    /// 車種専用累積距離PIDの適用型式です。
    let distanceSourceModelCode: String?
    /// セッションへ記録されたRaw応答件数です。
    let rawRecordCount: Int64
    /// Raw応答Payloadの合計バイト数です。
    let rawByteCount: Int64
    /// 現在端末のRawログ保管状態です。
    let localRawState: String
    /// CloudKit転送状態です。
    let cloudSyncState: String
    /// 転送PayloadのSHA-256です。
    let manifestDigest: String?
    /// 取り込んだMacの安定インストール識別子です。
    let macImportedDeviceID: String?
    /// 取り込んだMacの表示名です。
    let macImportedDeviceName: String?
    /// Mac取込検証日時です。
    let macImportedAt: Date?
    /// Macが検証したManifestのSHA-256です。
    let macImportedManifestDigest: String?

    /// DomainセッションをGRDB保存値へ変換します。
    ///
    /// 責務: 1件のDomain接続セッションを列指向の永続化表現へ変換します。
    /// - Parameter session: 永続化するDomainセッション。
    init(session: ConnectionSession) {
        id = session.id.rawValue.uuidString.lowercased()
        accountIdentifier = session.accountIdentifier
        startedAt = session.startedAt
        endedAt = session.endedAt
        endReason = session.endReason?.rawValue
        stopReviewDecision = session.stopReviewDecision?.rawValue
        vehicleID = session.vehicle?.id.rawValue.uuidString.lowercased()
        vehicleName = session.vehicle?.name
        vehicleDisplayIdentifier = session.vehicle?.displayIdentifier
        acquisitionPlatform = session.acquisitionDevice?.platform.rawValue
        acquisitionDeviceName = session.acquisitionDevice?.name
        startingOdometerKilometers = session.startingOdometerKilometers
        endingOdometerKilometers = session.endingOdometerKilometers
        distanceSourceModelCode = session.distanceSourceModelCode
        rawRecordCount = session.rawLogSummary.recordCount
        rawByteCount = session.rawLogSummary.byteCount
        localRawState = session.rawLogSummary.localState.rawValue
        cloudSyncState = session.rawLogSummary.cloudState.rawValue
        manifestDigest = session.rawLogSummary.manifestDigest
        macImportedDeviceID = session.rawLogSummary.macImportReceipt?.deviceID
        macImportedDeviceName = session.rawLogSummary.macImportReceipt?.deviceName
        macImportedAt = session.rawLogSummary.macImportReceipt?.importedAt
        macImportedManifestDigest = session.rawLogSummary.macImportReceipt?.manifestDigest
    }

    /// 永続化済み列からDomainセッションを復元します。
    ///
    /// 責務: 1件の検証済みGRDBレコードをDomain接続セッションへ復元します。
    /// - Returns: 復元できた接続セッション。不正な識別値または終了原因の場合は `nil`。
    func makeDomainSession() -> ConnectionSession? {
        guard let sessionUUID = UUID(uuidString: id),
              let localState = ConnectionSessionLocalRawState(rawValue: localRawState),
              let cloudState = ConnectionSessionCloudSyncState(rawValue: cloudSyncState) else { return nil }
        let reason: ConnectionSessionEndReason?
        if let endReason {
            guard let decoded = ConnectionSessionEndReason(rawValue: endReason) else { return nil }
            reason = decoded
        } else {
            reason = nil
        }
        let vehicle: ConnectionSessionVehicle?
        if let vehicleID, let vehicleName, let vehicleDisplayIdentifier,
           let vehicleUUID = UUID(uuidString: vehicleID) {
            vehicle = ConnectionSessionVehicle(
                id: VehicleID(rawValue: vehicleUUID),
                name: vehicleName,
                displayIdentifier: vehicleDisplayIdentifier
            )
        } else {
            vehicle = nil
        }
        var session = ConnectionSession(
            id: ConnectionSessionID(rawValue: sessionUUID),
            accountIdentifier: accountIdentifier,
            startedAt: startedAt,
            vehicle: vehicle,
            acquisitionDevice: acquisitionDevice
        )
        session.endedAt = endedAt
        session.endReason = reason
        if let stopReviewDecision {
            guard let decision = ConnectionSessionStopReviewDecision(rawValue: stopReviewDecision) else { return nil }
            session.stopReviewDecision = decision
        }
        session.startingOdometerKilometers = startingOdometerKilometers
        session.endingOdometerKilometers = endingOdometerKilometers
        session.distanceSourceModelCode = distanceSourceModelCode
        let receipt: ConnectionSessionMacImportReceipt?
        if let macImportedDeviceID,
           let macImportedDeviceName,
           let macImportedAt,
           let macImportedManifestDigest {
            receipt = ConnectionSessionMacImportReceipt(
                deviceID: macImportedDeviceID,
                deviceName: macImportedDeviceName,
                importedAt: macImportedAt,
                manifestDigest: macImportedManifestDigest
            )
        } else {
            receipt = nil
        }
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: rawRecordCount,
            byteCount: rawByteCount,
            localState: localState,
            cloudState: cloudState,
            manifestDigest: manifestDigest,
            macImportReceipt: receipt
        )
        return session
    }

    /// 保存済み列から取得元端末スナップショットを復元します。
    ///
    /// 責務: 取得元端末の任意列を有効なプラットフォームと端末名の組へ変換します。
    /// - Returns: 両方の列が有効な場合の取得元端末。旧レコードまたは不完全な列では `nil`。
    private var acquisitionDevice: ConnectionSessionAcquisitionDevice? {
        guard let acquisitionPlatform,
              let platform = ConnectionSessionAcquisitionPlatform(rawValue: acquisitionPlatform),
              let acquisitionDeviceName,
              !acquisitionDeviceName.isEmpty else { return nil }
        return ConnectionSessionAcquisitionDevice(platform: platform, name: acquisitionDeviceName)
    }
}
