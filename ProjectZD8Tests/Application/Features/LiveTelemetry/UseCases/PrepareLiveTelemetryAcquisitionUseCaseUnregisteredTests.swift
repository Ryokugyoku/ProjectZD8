import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両の取得準備が、ECUが対応を返した標準PIDだけを収集対象にすることを検証します。
@MainActor
final class PrepareLiveTelemetryAcquisitionUseCaseUnregisteredTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fake = BitmapOBDPIDTelemetryFake

    /// 対応を返した標準PIDだけが対象になり、対応を返さなかった標準PIDと車種専用PIDは入らず、車両別設定は使いません。
    ///
    /// 責務: 対象の定義・未登録車両用のcapability・車種専用PIDの問い合わせ0回・保存済み収集トグルの不使用を確認します。
    func testOnlySupportedStandardPIDsAreTargeted() async throws {
        let telemetry = Fake(bitmaps: [0x00: Fake.bitmap(supporting: [0x0C, 0x0D, 0x0F], base: 0x00, continues: false)])
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C, 0x0D]) + ZD8OBDPIDSeed.definitions
        let useCase = makeUseCase(catalog: catalog, telemetry: telemetry)

        let prepared = try await useCase.execute(vehicle: .unregistered, endpoint: LiveTelemetryTestDefinitions.endpoint)

        XCTAssertEqual(prepared.definitions.map(LiveTelemetryTestDefinitions.request), [0x0C, 0x0D].map(LiveTelemetryTestDefinitions.request))
        XCTAssertEqual(prepared.capabilities, [0x0C, 0x0D].map {
            ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(LiveTelemetryTestDefinitions.request($0))
        })
        XCTAssertTrue(prepared.capabilities.allSatisfy { $0.isCollectionEnabled && $0.support == .supported })
        XCTAssertEqual(telemetry.vehicleSpecificCallCount, 0)
    }

    /// 対応PIDの探索が失敗すると、空の対象にせずその失敗を送出します。
    ///
    /// 責務: 探索の応答欠落を取得準備の失敗にすることを確認します。
    func testDiscoveryFailureIsNotTurnedIntoEmptyTargets() async {
        let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), telemetry: Fake(bitmaps: [:]))

        do {
            _ = try await useCase.execute(vehicle: .unregistered, endpoint: LiveTelemetryTestDefinitions.endpoint)
            XCTFail("探索失敗なのに成功しました")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .noVehicleResponse)
        }
    }

    /// 対応PIDが0件、またはカタログに無いPIDだけなら、空の対象にせずカタログ利用不能として失敗します。
    ///
    /// 責務: 収集対象が空になる2つの場合を失敗にすることを確認します。
    func testNoSupportedCatalogPIDThrows() async {
        let cases: [[UInt8]] = [[], [0x0F, 0x1F]]
        for supported in cases {
            let telemetry = Fake(bitmaps: [0x00: Fake.bitmap(supporting: supported, base: 0x00, continues: false)])
            let useCase = makeUseCase(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), telemetry: telemetry)

            do {
                _ = try await useCase.execute(vehicle: .unregistered, endpoint: LiveTelemetryTestDefinitions.endpoint)
                XCTFail("収集対象が空なのに成功しました: \(supported)")
            } catch {
                XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
            }
        }
    }

    /// 登録済み車両では従来どおり、収集トグルを切ったPIDを除き、車種専用PIDも対象にします。
    ///
    /// 責務: 登録済み車両の取得準備が未登録車両の経路に影響されないことを確認します。
    func testRegisteredVehicleKeepsTogglesAndVehicleSpecificPIDs() async throws {
        let telemetry = Fake(bitmaps: [:])
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C]) + ZD8OBDPIDSeed.definitions
        let useCase = makeUseCase(catalog: catalog, telemetry: telemetry)

        let prepared = try await useCase.execute(
            vehicle: .registered(LiveTelemetryTestDefinitions.vehicleID, vehicleModelCode: ZD8VehicleModelPolicy.modelCode),
            endpoint: LiveTelemetryTestDefinitions.endpoint
        )

        XCTAssertFalse(prepared.definitions.contains { $0.pid == 0x05 && $0.service == 0x01 })
        XCTAssertTrue(prepared.definitions.contains { $0.isVehicleSpecific })
        XCTAssertEqual(telemetry.queriedPIDs, [])
    }

    /// カタログと、PID 0x05 の収集トグルを切った保存済みcapabilityで取得準備を作ります。
    ///
    /// 責務: 未登録の経路で車両別設定が使われていないことを見分けられる取得準備を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - telemetry: 取得境界のフェイク。
    /// - Returns: 取得準備のユースケース。
    private func makeUseCase(catalog: [OBDPIDDefinition], telemetry: Fake) -> PrepareLiveTelemetryAcquisitionUseCase {
        PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog), telemetry: telemetry),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: StubVehiclePIDCapabilityRepository(
                    capabilities: catalog.map { StubVehiclePIDCapabilityRepository.capability($0, enabled: !($0.service == 0x01 && $0.pid == 0x05)) }
                ),
                telemetry: telemetry
            ),
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry)
        )
    }
}
