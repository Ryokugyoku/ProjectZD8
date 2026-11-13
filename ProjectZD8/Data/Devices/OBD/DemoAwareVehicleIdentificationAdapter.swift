/// デモ終端と実終端を対応する車両識別境界へ振り分けます。
struct DemoAwareVehicleIdentificationAdapter: VehicleIdentificationPort {
    /// 実OBD通信を行う識別境界です。
    private let live: any VehicleIdentificationPort
    /// 物理通信なしで観測を返す識別境界です。
    private let demo: any VehicleIdentificationPort

    /// 実通信境界とデモ境界を保持して生成します。
    ///
    /// 責務: 2種類の車両識別境界を終端識別子による振分けへ固定します。
    /// - Parameters:
    ///   - live: 実終端を処理する識別境界。
    ///   - demo: デモ終端を処理する識別境界。
    init(live: any VehicleIdentificationPort, demo: any VehicleIdentificationPort) {
        self.live = live
        self.demo = demo
    }

    /// 終端識別子に対応する識別境界を実行します。
    ///
    /// 責務: 1件のOBD終端をデモまたは実車の識別処理へ振り分けます。
    /// - Parameter endpoint: 識別対象のOBD接続終端。
    /// - Returns: 選択した境界が返した車両識別観測。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        if DemoOBDAdapter.matches(endpoint) {
            return try await demo.identifyVehicle(using: endpoint)
        }
        return try await live.identifyVehicle(using: endpoint)
    }
}
