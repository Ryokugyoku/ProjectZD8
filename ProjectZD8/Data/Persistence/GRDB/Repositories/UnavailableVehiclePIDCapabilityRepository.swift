/// PID設定DBを準備できない場合に明示的失敗を返します。
struct UnavailableVehiclePIDCapabilityRepository: VehiclePIDCapabilityRepository, AccountVehiclePIDCapabilityErasureRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に読込失敗を通知します。
    ///
    /// 責務: 車両別PID設定読込を利用不能エラーへ変換します。
    /// - Parameter vehicleID: 使用しない車両ID。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に `UnavailableError`。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] { throw UnavailableError() }

    /// 常に初期登録失敗を通知します。
    ///
    /// 責務: 車両別PID初期登録を利用不能エラーへ変換します。
    /// - Parameters:
    ///   - capabilities: 使用しない対応PID。
    ///   - vehicleID: 使用しない車両ID。
    /// - Throws: 常に `UnavailableError`。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws { throw UnavailableError() }

    /// 利用不能な保存先では追加登録を失敗として返します。
    ///
    /// 責務: 専用PID追加要求を假成功にせず利用不能エラーへ変換します。
    /// - Parameters:
    ///   - capabilities: 保存しない対応PID。
    ///   - vehicleID: 使用しない車両ID。
    /// - Throws: 常に利用不能エラー。
    func mergeDiscovered(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws { throw UnavailableError() }

    /// 常に選択更新失敗を通知します。
    ///
    /// 責務: PID収集選択更新を利用不能エラーへ変換します。
    /// - Parameters:
    ///   - isEnabled: 使用しない選択状態。
    ///   - request: 使用しないPID。
    ///   - vehicleID: 使用しない車両ID。
    /// - Throws: 常に `UnavailableError`。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws { throw UnavailableError() }

    /// 車両別PID設定削除を利用不能として失敗させます。
    ///
    /// 責務: 車両ID群の設定削除要求を明示的な永続化利用不能へ変換します。
    /// - Parameter vehicleIDs: 削除できない車両ID群。
    /// - Throws: 常に `UnavailableError`。
    func deleteCapabilities(for vehicleIDs: [VehicleID]) throws { throw UnavailableError() }

    /// 永続化境界が利用不能であることを示します。
    private struct UnavailableError: Error {}
}
