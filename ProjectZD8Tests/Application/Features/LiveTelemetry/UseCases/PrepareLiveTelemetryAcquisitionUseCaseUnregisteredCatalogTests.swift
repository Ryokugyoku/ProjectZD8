import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両の取得準備で、PIDカタログの読込に失敗した時、空の対象にせずカタログ利用不能として失敗することを検証します。
@MainActor
final class PrepareLiveTelemetryAcquisitionUseCaseUnregisteredCatalogTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fake = BitmapOBDPIDTelemetryFake

    /// ECUが対応PIDを返しても、カタログを読めなければ `definitionCatalogUnavailable` を送出し、対象を返しません。
    ///
    /// 責務: 探索の成功後のカタログ読込失敗が、空データの成功へ潰されないことを確認します。
    func testCatalogReadFailurePropagatesForUnregisteredVehicle() async {
        let telemetry = Fake(bitmaps: [0x00: Fake.bitmap(supporting: [0x0C, 0x0D], base: 0x00, continues: false)])
        let useCase = PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: StubOBDPIDDefinitionRepository(definitions: LiveTelemetryTestDefinitions.standard([0x0C]), failsRead: true),
                telemetry: telemetry
            ),
            loadVehicleCapabilities: nil,
            discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry)
        )

        do {
            let prepared = try await useCase.execute(vehicle: .unregistered, endpoint: LiveTelemetryTestDefinitions.endpoint)
            XCTFail("カタログ読込失敗なのに成功しました: \(prepared.definitions.count)件")
        } catch {
            XCTAssertEqual(error as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        }
        XCTAssertEqual(telemetry.queriedPIDs, [0x00])
    }
}
