/// HOME接続要求から車両接続開始ワークフローを起動します。
@MainActor
struct StartVehicleConnectionUseCase {
    /// 新しい接続セッションの開始を通知する注入済み処理です。
    private let startConnectionSession: @MainActor () -> Void
    /// 車両識別開始を通知する注入済み処理です。
    private let identifyVehicle: @MainActor (OBDConnectionEndpoint) -> Void
    /// リアルタイムPID取得開始を通知する注入済み処理です。
    private let startLiveTelemetry: @MainActor (OBDConnectionEndpoint) -> Void

    /// セッション開始、車両識別、Telemetry開始の通知先を保持して生成します。
    ///
    /// 責務: HOME接続開始を構成する3件のApplication通知先を固定します。
    /// - Parameters:
    ///   - startConnectionSession: Loggingへ新規セッション開始を通知する処理。
    ///   - identifyVehicle: VehicleManagementへ識別開始を通知する処理。
    ///   - startLiveTelemetry: LiveTelemetryへ継続取得開始を通知する処理。
    init(
        startConnectionSession: @escaping @MainActor () -> Void = {},
        identifyVehicle: @escaping @MainActor (OBDConnectionEndpoint) -> Void,
        startLiveTelemetry: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        self.startConnectionSession = startConnectionSession
        self.identifyVehicle = identifyVehicle
        self.startLiveTelemetry = startLiveTelemetry
    }

    /// 指定終端に対するセッション、車両識別、PID継続取得を開始します。
    ///
    /// 責務: 1件のHOME接続要求に対応する接続開始ワークフローを起動します。
    /// - Parameter endpoint: 接続対象として選択されたOBD終端。
    func execute(endpoint: OBDConnectionEndpoint) {
        startConnectionSession()
        identifyVehicle(endpoint)
        startLiveTelemetry(endpoint)
    }
}
