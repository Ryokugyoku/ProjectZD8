@testable import ProjectZD8

/// 車両確認の fake です。渡されたタイムアウト種別を記録し、結果は台本かテストからの後渡しで決めます。
@MainActor
final class VehicleResponseConfirmationFake: VehicleResponseConfirmationPort {
    /// 結果の台本と保留中の呼び出しです。
    let responses = AdapterLinkSupervisionScriptedResponses<VehicleResponseOutcome>()

    /// 呼び出しごとに渡されたタイムアウト種別です。
    private(set) var timeouts: [VehicleResponseTimeout] = []

    /// 確認の結果を返します。
    ///
    /// 責務: タイムアウト種別を記録して台本か後渡しの結果を返します。
    /// - Parameter timeout: 通常か最大のタイムアウト。
    /// - Returns: ECU応答の有無。
    func confirmVehicleResponse(timeout: VehicleResponseTimeout) async throws -> VehicleResponseOutcome {
        timeouts.append(timeout)
        return try await responses.next()
    }
}
