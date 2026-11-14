import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両用に、ECUが対応を返した標準PIDの定義だけをカタログから選ぶことを検証します。
@MainActor
final class ReadMajorOBDPIDsUseCaseStandardDefinitionsTests: XCTestCase {
    /// 対応を返した数値化可能な標準PIDだけを選び、車種専用PIDは対応一覧にあっても選びません。
    ///
    /// 責務: 対応の有無・数値化の可否・車種専用の3つの条件での選別を確認します。
    func testSelectsSupportedDecodableStandardDefinitionsOnly() throws {
        let undecodable = OBDPIDDefinition(
            service: 0x01, pid: 0x0D, nameKey: "test.undecodable", requiredByteCount: nil, formula: nil,
            unit: "unit", minimumValue: nil, maximumValue: nil, sourceURI: "test://pid", revision: 1
        )
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C]) + [undecodable] + ZD8OBDPIDSeed.definitions
        let supported = [0x0C, 0x0D].map(LiveTelemetryTestDefinitions.request)
            + ZD8OBDPIDSeed.definitions.map(LiveTelemetryTestDefinitions.request)

        let definitions = try makeUseCase(catalog: catalog).loadStandardDefinitions(supported: supported)

        XCTAssertEqual(definitions.map(LiveTelemetryTestDefinitions.request), [LiveTelemetryTestDefinitions.request(0x0C)])
    }

    /// 選べる定義が無い、またはカタログを読めなければ、カタログ利用不能として失敗します。
    ///
    /// 責務: 空の結果と読込失敗を成功にしないことを確認します。
    func testEmptyOrUnreadableCatalogThrows() {
        let cases = [
            makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x05])),
            makeUseCase(catalog: [], failsRead: true)
        ]
        for useCase in cases {
            XCTAssertThrowsError(try useCase.loadStandardDefinitions(supported: [LiveTelemetryTestDefinitions.request(0x0C)])) {
                XCTAssertEqual($0 as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            }
        }
    }

    /// カタログを指定して定義読込のユースケースを作ります。
    ///
    /// 責務: 通信しない取得境界で定義読込のユースケースを返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - failsRead: カタログ読込を失敗させる場合は `true`。
    /// - Returns: 定義読込のユースケース。
    private func makeUseCase(catalog: [OBDPIDDefinition], failsRead: Bool = false) -> ReadMajorOBDPIDsUseCase {
        ReadMajorOBDPIDsUseCase(
            definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog, failsRead: failsRead),
            telemetry: ScriptedOBDPIDTelemetryFake()
        )
    }
}
