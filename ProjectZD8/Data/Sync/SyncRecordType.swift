/// iCloudへ同期するレコードの種類です。生の値がCloudKitのレコードタイプ名になります。
///
/// 旧版の本番スキーマとは互換性を持たない新しい名前です。
nonisolated enum SyncRecordType: String, CaseIterable, Codable, Sendable {
    /// 車両。全ての子レコードの親です。
    case vehicle = "RTVehicle"
    /// 整備記録。
    case maintenanceRecord = "RTMaintenanceRecord"
    /// 写真。画像本体を `CKAsset` として持ちます。
    case photo = "RTPhoto"
    /// 終了済みの走行セッション。Rawアーカイブを `CKAsset` として持ちます。
    case driveSession = "RTDriveSession"

    /// 対応するローカルテーブル名です。
    var tableName: String {
        switch self {
        case .vehicle: "vehicles"
        case .maintenanceRecord: "maintenance_records"
        case .photo: "photos"
        case .driveSession: "sessions"
        }
    }

    /// 送信順です。親(車両)を先に保存し、子の参照が解決できるようにします。
    var sendOrder: Int {
        switch self {
        case .vehicle: 0
        case .photo: 1
        case .maintenanceRecord: 2
        case .driveSession: 3
        }
    }

    /// 車両に所属する子レコードかどうかです。
    var isVehicleChild: Bool { self != .vehicle }
}
