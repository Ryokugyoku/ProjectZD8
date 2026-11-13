import CloudKit

/// iCloud同期で使うコンテナとゾーンの定数です。
nonisolated enum CloudKitSyncConfiguration {
    /// CloudKitコンテナの識別子です。エンタイトルメントの `icloud-container-identifiers` と一致させます。
    static let containerIdentifier = "iCloud.Ryokugyoku.ProjectZD8"
    /// `CKSyncEngine` が管理する、属性レコードのカスタムゾーン名です。
    static let zoneName = "RevTorqueInsight"
    /// セッションのRawアーカイブだけを置くカスタムゾーン名です。
    ///
    /// `CKSyncEngine` の取得対象から外し、復元時にだけ直接取得します(全端末が全Rawを自動ダウンロードしないため)。
    static let archiveZoneName = "RevTorqueInsightArchives"

    /// 責務: 属性レコードのゾーンIDを返します(現在のユーザーのプライベートデータベース)。
    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// 責務: アーカイブのゾーンIDを返します(現在のユーザーのプライベートデータベース)。
    static var archiveZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: archiveZoneName, ownerName: CKCurrentUserDefaultName)
    }
}
