/// 1件のPID要求を送り、その結果をTransport観測へ変換します。
nonisolated struct OBDPIDSingleRequestReader: Sendable {
    /// PID単位のtyped Transport観測を返す取得境界です。
    private let telemetry: any OBDPIDTelemetryPort

    /// 取得境界を固定します。
    ///
    /// 責務: 1件ずつ要求を送る読取を取得境界へ結び付けます。
    /// - Parameter telemetry: PID単位のtyped Transport観測を返す取得境界。
    init(telemetry: any OBDPIDTelemetryPort) {
        self.telemetry = telemetry
    }

    /// 1件のPIDを送り、結果を受けるまで待ちます。
    ///
    /// 責務: 1要求だけを実行し、throwや観測不一致を非対応と推測しない排他結果へ変換します。
    /// - Parameters:
    ///   - definition: 送る取得時PID定義。車種専用定義は専用経路で送ります。
    ///   - endpoint: 使用するOBD終端。
    /// - Returns: 明示typed結果、または取消・通信失敗・未分類の結果。
    func read(
        _ definition: OBDPIDDefinition,
        using endpoint: OBDConnectionEndpoint
    ) async -> OBDPIDRequestTransportOutcome {
        let request = OBDPIDRequest(service: definition.service, pid: definition.pid)
        do {
            if definition.isVehicleSpecific {
                let responses = try await telemetry.readVehicleSpecific([definition], using: endpoint)
                guard let payload = responses[request] else { return .unclassifiedResponse }
                return .responded(payload)
            }
            let observations = try await telemetry.readObservations([request], using: endpoint)
            guard observations.count == 1, observations[0].request == request else {
                return .unclassifiedResponse
            }
            return observations[0].outcome
        } catch is CancellationError {
            return .cancelled
        } catch let error as OBDPIDTelemetryError {
            return Self.outcome(for: error)
        } catch {
            return .unclassifiedResponse
        }
    }

    /// 取得境界が送出したエラーをTransport観測へ分類します。
    ///
    /// 責務: 通信境界の喪失だけを通信失敗とし、それ以外を未分類へ変換します。
    /// - Parameter error: 取得境界が送出したエラー。
    /// - Returns: 通信失敗または未分類の結果。
    private static func outcome(for error: OBDPIDTelemetryError) -> OBDPIDRequestTransportOutcome {
        switch error {
        case .connectionLost, .unavailable:
            return .transportFailure
        case .definitionCatalogUnavailable, .unsupportedPID, .commandRejected,
             .malformedResponse, .incompleteResponse, .noVehicleResponse:
            return .unclassifiedResponse
        }
    }
}
