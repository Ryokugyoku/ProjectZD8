/// 車両単位の対応PIDと収集選択を永続化する能力です。
protocol VehiclePIDCapabilityRepository: Sendable {
    /// 指定車両で確認済みの対応PIDを取得します。
    ///
    /// 責務: 1件の車両IDに属する対応PID設定をService/PID順で返します。
    /// - Parameter vehicleID: 照会するアプリ内車両識別子。
    /// - Returns: 確認済み対応PID設定。
    /// - Throws: 永続読込に失敗した場合のエラー。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability]

    /// 未収集車両へ対応PIDを全件収集有効で登録します。
    ///
    /// 責務: 0件の車両スコープへ1回の探索結果を原子的に初期登録します。
    /// - Parameters:
    ///   - capabilities: 登録する対応PID設定。
    ///   - vehicleID: 登録先のアプリ内車両識別子。
    /// - Throws: 既存データまたは永続書込失敗の場合のエラー。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws

    /// 応答確認済みPIDを既存の収集選択を変えず追加します。
    ///
    /// 責務: 1台の車両へ新たに応答したPIDだけを非破壊で登録します。
    /// - Parameters:
    ///   - capabilities: 新たに応答確認できたPID設定。
    ///   - vehicleID: 登録先の車両識別子。
    /// - Throws: 車両不一致または永続書込失敗の場合のエラー。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws

    /// 1件の対応PIDの収集選択を更新します。
    ///
    /// 責務: 指定車両の指定PIDだけの収集有効状態を変更します。
    /// - Parameters:
    ///   - isEnabled: 新しい収集有効状態。
    ///   - request: 更新するService/PID。
    ///   - vehicleID: 更新対象の車両識別子。
    /// - Throws: 対象不在または永続書込失敗の場合のエラー。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws
}
