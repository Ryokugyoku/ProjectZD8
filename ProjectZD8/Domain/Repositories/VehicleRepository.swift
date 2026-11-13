/// 登録車両の永続化契約です。
nonisolated protocol VehicleRepository: Sendable {
    /// 責務: 削除されていない全車両を名称順で返します。
    func vehicles() async throws -> [Vehicle]
    /// 責務: IDに一致する車両を返します。無ければ `nil` を返します。
    func vehicle(_ id: VehicleID) async throws -> Vehicle?
    /// 責務: 車両を新規保存または上書きします。
    func save(_ vehicle: Vehicle) async throws
    /// 責務: 車両と、その車両に属するセッション・整備記録・写真・PID設定をまとめて削除します。
    func delete(_ id: VehicleID) async throws
}
