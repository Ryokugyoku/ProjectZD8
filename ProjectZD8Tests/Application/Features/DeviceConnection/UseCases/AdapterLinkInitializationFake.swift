@testable import ProjectZD8

/// アダプター初期化の fake です。結果は台本かテストからの後渡しで決めます。
@MainActor
final class AdapterLinkInitializationFake: AdapterLinkInitializationPort {
    /// 結果の台本と保留中の呼び出しです。
    let responses = AdapterLinkSupervisionScriptedResponses<AcquisitionAdapterProbeEvidence>()

    /// 初期化の結果を返します。
    ///
    /// 責務: 呼び出しを記録して台本か後渡しの結果を返します。
    /// - Returns: アダプター判定結果。
    func initializeAdapter() async throws -> AcquisitionAdapterProbeEvidence {
        try await responses.next()
    }
}
