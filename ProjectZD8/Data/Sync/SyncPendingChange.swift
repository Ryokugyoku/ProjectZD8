/// ローカルのテーブルから導いた、iCloudへ未送信の1件の変更です。
nonisolated struct SyncPendingChange: Hashable, Sendable {
    /// 変更の種類です。
    nonisolated enum Kind: Hashable, Sendable {
        /// 新規または更新の保存。
        case save
        /// 削除済み(墓標)行の削除。
        case delete
    }

    let recordType: SyncRecordType
    let recordName: String
    let kind: Kind

    /// 責務: 1件の未送信変更を生成します。
    init(recordType: SyncRecordType, recordName: String, kind: Kind) {
        self.recordType = recordType
        self.recordName = recordName
        self.kind = kind
    }
}
