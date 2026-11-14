/// 取得を始める車両が登録済みか未登録かを表します。
///
/// 登録済みなら車両別の対応PIDと収集トグル、確認済み型式コードの車種専用PIDを使います。
/// 未登録ならECUが対応を返した標準PIDだけを、すべて収集対象として使います。
nonisolated enum LiveTelemetryVehicleContext: Equatable, Sendable {
    /// 登録済みの車両です。
    /// - Parameters:
    ///   - id: 対応PID設定を参照するアプリ内車両ID。
    ///   - vehicleModelCode: 車種専用PIDを適用する確認済み型式コード。確認できなければ `nil`。
    case registered(VehicleID, vehicleModelCode: String?)
    /// 登録されていない車両です。車両別設定と車種専用PIDを使いません。
    case unregistered

    /// 登録済み車両のIDを返します。
    ///
    /// 責務: 登録済みならID、未登録なら `nil` へ変換します。
    var vehicleID: VehicleID? {
        if case let .registered(id, _) = self { return id }
        return nil
    }

    /// 車種専用PIDを適用する型式コードを返します。
    ///
    /// 責務: 登録済みで型式が確認済みの場合だけ型式コードを返します。未登録は常に `nil` です。
    var vehicleModelCode: String? {
        if case let .registered(_, code) = self { return code }
        return nil
    }
}
