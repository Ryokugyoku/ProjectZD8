/// HOME接続要求から車両接続開始ワークフローを起動します。
@MainActor
struct StartVehicleConnectionUseCase {
    /// 車両識別開始を通知する注入済み処理です。
    private let identifyVehicle: @MainActor (OBDConnectionEndpoint) -> Void

    /// 車両識別の通知先を保持して生成します。
    ///
    /// 責務: HOME接続開始を構成する車両識別通知先を固定します。
    /// - Parameter identifyVehicle: VehicleManagementへ識別開始を通知する処理。
    init(
        identifyVehicle: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        self.identifyVehicle = identifyVehicle
    }

    /// 指定終端に対する車両識別を開始します。
    ///
    /// 責務: 1件のHOME接続要求を車両確定前の識別段階へ進めます。
    /// - Parameter endpoint: 接続対象として選択されたOBD終端。
    func execute(endpoint: OBDConnectionEndpoint) {
        identifyVehicle(endpoint)
    }
}
