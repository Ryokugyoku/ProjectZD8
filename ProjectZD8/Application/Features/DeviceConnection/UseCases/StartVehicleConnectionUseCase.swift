/// HOME接続要求から車両接続開始ワークフローを起動します。
@MainActor
struct StartVehicleConnectionUseCase {
    /// 新しい接続セッションの開始を通知する注入済み処理です。
    private let startConnectionSession: @MainActor () -> Void
    /// 車両識別開始を通知する注入済み処理です。
    private let identifyVehicle: @MainActor (OBDConnectionEndpoint) -> Void

    /// セッション開始と車両識別の通知先を保持して生成します。
    ///
    /// 責務: HOME接続開始を構成する2件のApplication通知先を固定します。
    /// - Parameters:
    ///   - startConnectionSession: Loggingへ新規セッション開始を通知する処理。
    ///   - identifyVehicle: VehicleManagementへ識別開始を通知する処理。
    init(
        startConnectionSession: @escaping @MainActor () -> Void = {},
        identifyVehicle: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        self.startConnectionSession = startConnectionSession
        self.identifyVehicle = identifyVehicle
    }

    /// 指定終端に対するセッションと車両識別を開始します。
    ///
    /// 責務: 1件のHOME接続要求に対応する接続開始ワークフローを起動します。
    /// - Parameter endpoint: 接続対象として選択されたOBD終端。
    func execute(endpoint: OBDConnectionEndpoint) {
        startConnectionSession()
        identifyVehicle(endpoint)
    }
}
