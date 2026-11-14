/// 車両識別の結果を、接続セッションの開始・車両の関連付けとPID継続取得の開始へつなぐ配線です。
///
/// iOSとmacOSで同じ配線を共有し、各OSの組み立てにコピーしません。
@MainActor
enum VehicleConnectionStartWiring {
    /// 登録済み車両で接続を始めます。
    ///
    /// 責務: 新しいセッションの開始、車両の関連付け、型式コードを適用したPID継続取得の開始を順に通知します。
    /// - Parameters:
    ///   - vehicle: 識別で照合できた登録済み車両。
    ///   - endpoint: 接続するOBD終端。
    ///   - identification: 識別したVINまたはOBD識別子。
    ///   - lifecycle: 接続セッションのライフサイクル。
    ///   - liveTelemetry: PID継続取得のモデル。
    static func startRegistered(
        _ vehicle: VehicleProfile,
        endpoint: OBDConnectionEndpoint,
        identification: VehicleIdentificationSnapshot,
        lifecycle: ConnectionSessionLifecycleModel,
        liveTelemetry: LiveTelemetryModel
    ) {
        lifecycle.send(.startRequested)
        lifecycle.send(.vehicleResolved(vehicle))
        let policy = ZD8VehicleModelPolicy()
        let vehicleModelCode = policy.matches(identification.vin) || policy.matches(identification.obdIdentifier)
            ? ZD8VehicleModelPolicy.modelCode
            : nil
        liveTelemetry.send(.startRequested(endpoint, .registered(vehicle.id, vehicleModelCode: vehicleModelCode)))
    }

    /// 未登録車両で接続を始めます。
    ///
    /// 責務: 新しいセッションの開始(車両なし)と、標準PIDだけのPID継続取得の開始を順に通知します。
    /// - Parameters:
    ///   - endpoint: 接続するOBD終端。
    ///   - lifecycle: 接続セッションのライフサイクル。
    ///   - liveTelemetry: PID継続取得のモデル。
    static func startUnregistered(
        endpoint: OBDConnectionEndpoint,
        lifecycle: ConnectionSessionLifecycleModel,
        liveTelemetry: LiveTelemetryModel
    ) {
        lifecycle.send(.startRequested)
        lifecycle.send(.vehicleUnregistered)
        liveTelemetry.send(.startRequested(endpoint, .unregistered))
    }
}
