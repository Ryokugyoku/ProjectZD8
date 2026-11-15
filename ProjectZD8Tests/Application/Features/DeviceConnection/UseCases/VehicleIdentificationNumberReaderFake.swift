@testable import ProjectZD8

/// VIN読取の fake です。結果は台本かテストからの後渡しで決めます。
@MainActor
final class VehicleIdentificationNumberReaderFake: VehicleIdentificationNumberReadingPort {
    /// 結果の台本と保留中の呼び出しです。
    let responses = AdapterLinkSupervisionScriptedResponses<String?>()

    /// VINの読取結果を返します。
    ///
    /// 責務: 呼び出しを記録して台本か後渡しの結果を返します。
    /// - Returns: 読み取ったVIN。
    func readVehicleIdentificationNumber() async throws -> String? {
        try await responses.next()
    }
}
