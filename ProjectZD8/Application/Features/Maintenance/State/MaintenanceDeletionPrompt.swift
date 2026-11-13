/// 整備記録削除の確認画面へ表示する内容です。
nonisolated struct MaintenanceDeletionPrompt: Equatable, Sendable {
    /// 削除対象の記録IDです。
    let recordID: MaintenanceRecordID
    /// 削除対象の表題です。
    let title: String
    /// 一緒に削除される写真の枚数です。
    let photoCount: Int
}
