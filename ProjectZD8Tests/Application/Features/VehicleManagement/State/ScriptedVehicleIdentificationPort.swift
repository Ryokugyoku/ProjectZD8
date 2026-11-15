import Foundation
@testable import ProjectZD8

/// 車両識別の結果を台本で決め、呼び出しを記録し、指定時は応答を保留する車両識別ポートの fake です。
@MainActor
final class ScriptedVehicleIdentificationPort: VehicleIdentificationPort {
    /// 識別要求で返す結果です。
    var result: Result<VehicleIdentificationSnapshot, any Error>

    /// 設定されている場合、識別はこの台本の応答を待ってから結果を返します。
    var gate: AdapterLinkSupervisionScriptedResponses<Bool>?

    /// 識別要求を受けるたびに呼ぶ処理です。呼び出し順の記録に使います。
    var identificationDidStart: (@MainActor () -> Void)?

    /// 識別要求の回数です。
    private(set) var callCount = 0

    /// 返す結果を固定して生成します。
    ///
    /// 責務: 台本の初期結果を設定します。
    /// - Parameter result: 識別要求で返す結果。
    init(result: Result<VehicleIdentificationSnapshot, any Error>) {
        self.result = result
    }

    /// 台本の結果を返します。
    ///
    /// 責務: 呼び出しを記録し、保留指定があれば待ってから、台本の結果を返すか throw します。
    /// - Parameter endpoint: 使用しない接続終端。
    /// - Returns: 台本の識別観測。
    /// - Throws: 台本のエラー、または保留中の取り消し。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot {
        callCount += 1
        identificationDidStart?()
        if let gate { _ = try await gate.next() }
        return try result.get()
    }
}
