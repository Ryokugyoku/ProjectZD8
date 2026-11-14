import Foundation
import XCTest
@testable import ProjectZD8

/// 取得開始前に、車両の収集トグルとPIDカタログから取得対象とcapabilityを確定することを検証します。
@MainActor
final class PrepareLiveTelemetryAcquisitionUseCaseTests: XCTestCase {
    /// 収集トグルを切ったPIDは、取得対象の定義とcapabilityのどちらにも入りません。
    ///
    /// 責務: 保存済みcapabilityの収集無効PIDを取り除き、残りを定義順の対応済みcapabilityへ変換することを確認します。
    func testCollectionDisabledPIDIsExcludedFromDefinitionsAndCapabilities() async throws {
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C, 0x0D])
        let useCase = makeUseCase(catalog: catalog, capabilities: catalog.map {
            StubVehiclePIDCapabilityRepository.capability($0, enabled: $0.pid != 0x0C)
        })

        let prepared = try await execute(useCase)

        XCTAssertEqual(prepared.definitions.map(\.pid), [0x05, 0x0D])
        XCTAssertEqual(prepared.capabilities, [0x05, 0x0D].map {
            ConnectionSessionAcquisitionPIDCapabilityInput(
                request: LiveTelemetryTestDefinitions.request($0),
                support: .supported,
                isCollectionEnabled: true
            )
        })
    }

    /// 定義の無いcapabilityとcapabilityの無い定義は取得対象に入りません。
    ///
    /// 責務: カタログと車両capabilityの両方にあるPIDだけを取得対象にすることを確認します。
    func testOnlyPIDsPresentInBothCatalogAndCapabilitiesAreTargeted() async throws {
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C])
        let capabilities = LiveTelemetryTestDefinitions.standard([0x0C, 0x0F]).map {
            StubVehiclePIDCapabilityRepository.capability($0, enabled: true)
        }
        let useCase = makeUseCase(catalog: catalog, capabilities: capabilities)

        let prepared = try await execute(useCase)

        XCTAssertEqual(prepared.definitions.map(\.pid), [0x0C])
        XCTAssertEqual(prepared.capabilities.map(\.request), [LiveTelemetryTestDefinitions.request(0x0C)])
    }

    /// 全PIDの収集トグルが切られていれば、空の取得対象ではなくカタログ利用不能として失敗します。
    ///
    /// 責務: 収集対象が空の場合を成功や空データに潰さないことを確認します。
    func testAllCollectionDisabledThrowsInsteadOfEmptyTargets() async {
        let catalog = LiveTelemetryTestDefinitions.standard([0x0C])
        let useCase = makeUseCase(catalog: catalog, capabilities: catalog.map {
            StubVehiclePIDCapabilityRepository.capability($0, enabled: false)
        })

        do {
            _ = try await execute(useCase)
            XCTFail("収集対象が空なのに成功しました")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
    }

    /// 車両capabilityを使わない構成では、数値化可能な全定義を対象にし、capabilityは空です。
    ///
    /// 責務: capability読込が未設定の経路で、数値化できない定義だけを除くことを確認します。
    func testWithoutCapabilityLoaderUsesAllDecodableDefinitions() async throws {
        let undecodable = OBDPIDDefinition(
            service: 0x01, pid: 0x20, nameKey: "test.undecodable", requiredByteCount: nil, formula: nil,
            unit: "unit", minimumValue: nil, maximumValue: nil, sourceURI: "test://pid", revision: 1
        )
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C]) + [undecodable]
        let useCase = PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog),
                telemetry: ScriptedOBDPIDTelemetryFake()
            ),
            loadVehicleCapabilities: nil,
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: ScriptedOBDPIDTelemetryFake())
        )

        let prepared = try await execute(useCase)

        XCTAssertEqual(prepared.definitions.map(\.pid), [0x05, 0x0C])
        XCTAssertEqual(prepared.capabilities, [])
    }

    /// PIDカタログを読めなければカタログ利用不能として失敗します。
    ///
    /// 責務: 定義読込の失敗を専用エラーへ変換することを確認します。
    func testCatalogReadFailureThrowsCatalogUnavailable() async {
        let useCase = PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: StubOBDPIDDefinitionRepository(definitions: [], failsRead: true),
                telemetry: ScriptedOBDPIDTelemetryFake()
            ),
            loadVehicleCapabilities: nil,
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: ScriptedOBDPIDTelemetryFake())
        )

        do {
            _ = try await execute(useCase)
            XCTFail("カタログ読込失敗なのに成功しました")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
    }

    /// 接続資源の解放をPID取得境界へ伝えます。
    ///
    /// 責務: `endSession` が取得境界の `endSession` を1回呼ぶことを確認します。
    func testEndSessionReleasesTelemetrySession() async {
        let telemetry = ScriptedOBDPIDTelemetryFake()
        let useCase = PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: StubOBDPIDDefinitionRepository(definitions: []), telemetry: telemetry),
            loadVehicleCapabilities: nil,
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry)
        )

        await useCase.endSession()

        XCTAssertEqual(telemetry.endSessionCount, 1)
    }

    /// 保存済みcapabilityを使う取得準備を生成します。
    ///
    /// 責務: 初回探索を起こさないcapability読込を持つ取得準備を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - capabilities: 保存済みcapability。
    /// - Returns: 取得準備のユースケース。
    private func makeUseCase(catalog: [OBDPIDDefinition], capabilities: [VehiclePIDCapability]) -> PrepareLiveTelemetryAcquisitionUseCase {
        let telemetry = ScriptedOBDPIDTelemetryFake()
        return PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog),
                telemetry: telemetry
            ),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: StubVehiclePIDCapabilityRepository(capabilities: capabilities),
                telemetry: telemetry
            ),
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry)
        )
    }

    /// テスト車両・終端で取得準備を実行します。
    ///
    /// 責務: 型式なしの登録済みテスト車両・テスト終端で `execute` を呼びます。
    /// - Parameter useCase: 実行する取得準備。
    /// - Returns: 取得対象の定義とcapability。
    /// - Throws: 取得準備のエラー。
    private func execute(
        _ useCase: PrepareLiveTelemetryAcquisitionUseCase
    ) async throws -> (definitions: [OBDPIDDefinition], capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]) {
        try await useCase.execute(
            vehicle: .registered(LiveTelemetryTestDefinitions.vehicleID, vehicleModelCode: nil),
            endpoint: LiveTelemetryTestDefinitions.endpoint
        )
    }
}
