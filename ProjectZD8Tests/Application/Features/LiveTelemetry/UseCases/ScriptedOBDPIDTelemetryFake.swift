import Foundation
@testable import ProjectZD8

/// 指定した観測・応答・エラーを即座に返し、受けた要求を記録するPID取得境界のフェイクです。
@MainActor
final class ScriptedOBDPIDTelemetryFake: OBDPIDTelemetryPort {
    /// `readObservations` が返す結果です。
    var observationsResult: Result<[OBDPIDRequestTransportObservation], any Error> = .success([])
    /// `readVehicleSpecific` が返す結果です。
    var vehicleSpecificResult: Result<[OBDPIDRequest: [UInt8]], any Error> = .success([:])
    /// `readObservations` に渡された要求です。呼び出し順に並びます。
    private(set) var observationRequests: [[OBDPIDRequest]] = []
    /// `readVehicleSpecific` に渡された定義です。呼び出し順に並びます。
    private(set) var vehicleSpecificDefinitions: [[OBDPIDDefinition]] = []
    /// `endSession` が呼ばれた回数です。
    private(set) var endSessionCount = 0

    /// 空の結果で生成します。
    ///
    /// 責務: 何も返さない既定の結果を持つフェイクを構築します。
    init() {}

    /// 指定した観測を返します。
    ///
    /// 責務: 要求を記録し、指定した観測またはエラーを返します。
    /// - Parameters:
    ///   - requests: 送られた要求。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 指定した観測。
    /// - Throws: 指定したエラー。
    func readObservations(
        _ requests: [OBDPIDRequest],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequestTransportObservation] {
        observationRequests.append(requests)
        return try observationsResult.get()
    }

    /// 指定した観測の正応答だけを辞書で返します。
    ///
    /// 責務: `readObservations` と同じ結果から正応答のpayloadを返します。
    /// - Parameters:
    ///   - requests: 送られた要求。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 正応答の要求とpayload。
    /// - Throws: 指定したエラー。
    func read(_ requests: [OBDPIDRequest], using endpoint: OBDConnectionEndpoint) async throws -> [OBDPIDRequest: [UInt8]] {
        let observations = try await readObservations(requests, using: endpoint)
        return Dictionary(uniqueKeysWithValues: observations.compactMap { observation in
            guard case let .responded(payload) = observation.outcome else { return nil }
            return (observation.request, payload)
        })
    }

    /// 指定した車種専用応答を返します。
    ///
    /// 責務: 定義を記録し、指定した応答またはエラーを返します。
    /// - Parameters:
    ///   - definitions: 送られた車種専用定義。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 指定した応答。
    /// - Throws: 指定したエラー。
    func readVehicleSpecific(
        _ definitions: [OBDPIDDefinition],
        using endpoint: OBDConnectionEndpoint
    ) async throws -> [OBDPIDRequest: [UInt8]] {
        vehicleSpecificDefinitions.append(definitions)
        return try vehicleSpecificResult.get()
    }

    /// 接続資源の解放を記録します。
    ///
    /// 責務: `endSession` の呼び出し回数を数えます。
    func endSession() async {
        endSessionCount += 1
    }
}
