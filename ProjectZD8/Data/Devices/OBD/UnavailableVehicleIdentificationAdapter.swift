/// 実OBD識別プロトコルが提供されるまで明示的に利用不能を返します。
struct UnavailableVehicleIdentificationAdapter: VehicleIdentificationPort {
    /// 呼び出し元へ返す利用不能理由です。
    private let error: VehicleIdentificationError

    /// 利用不能理由を保持する境界を生成します。
    ///
    /// 責務: 1件の製品構成上の利用不能理由を識別境界へ固定します。
    /// - Parameter error: すべての識別要求へ返す理由。
    init(error: VehicleIdentificationError = .unavailable) {
        self.error = error
    }

    /// 実装未提供を成功へ変換せず通知します。
    ///
    /// 責務: OBD識別の未提供状態を型付き失敗として返します。
    /// - Returns: この実装は値を返しません。
    /// - Parameter endpoint: 使用されない接続終端。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        throw error
    }
}
