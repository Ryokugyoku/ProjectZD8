/// 車両削除の確認画面へ表示する内容です。
nonisolated struct VehicleDeletionPrompt: Equatable, Sendable {
    /// 削除対象の車両IDです。
    let vehicleID: VehicleID
    /// 削除対象の車両名です。
    let vehicleName: String
    /// 一緒に削除されるセッションの件数です。
    let sessionCount: Int
}
