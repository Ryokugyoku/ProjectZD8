import Foundation

/// 物理通信なしで決定的なデモ車両識別観測を返します。
struct DemoVehicleIdentificationAdapter: VehicleIdentificationPort {
    /// 観測日時を提供する注入済みクロックです。
    private let now: @Sendable () -> Date

    /// 観測日時の供給元を保持して生成します。
    ///
    /// 責務: デモ車両識別観測を1件の注入済みクロックへ固定します。
    /// - Parameter now: 観測完了日時の供給元。
    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// デモVINと車両情報を実通信観測と同じ型で返します。
    ///
    /// 責務: デモ終端への1件の識別要求を通常登録可能な車両観測へ変換します。
    /// - Parameter endpoint: デモOBD接続終端。
    /// - Returns: 検査文字を含む合成VINとデモ車両フィールド。
    /// - Throws: デモ以外の終端では `VehicleIdentificationError.transportUnsupported`。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        guard DemoOBDAdapter.matches(endpoint) else { throw VehicleIdentificationError.transportUnsupported }
        let syntheticVIN = DemoOBDAdapter.syntheticVIN(for: endpoint)
        return VehicleIdentificationSnapshot(
            vin: syntheticVIN,
            fields: [
                .init(id: "manufacturer", label: "Manufacturer", value: "ProjectZD8 Demo Motors", source: endpoint.displayName),
                .init(id: "engineModel", label: "Engine Model", value: "ZD8-SIM-24", source: endpoint.displayName),
                .init(id: "obdProtocol", label: "OBD Protocol", value: "ISO 15765-4 (simulated)", source: endpoint.displayName)
            ],
            rawResponses: [
                .init(requestID: "vehicleIdentificationNumber", payload: "49 02 01 \(syntheticVIN)")
            ],
            observedAt: now()
        )
    }
}
