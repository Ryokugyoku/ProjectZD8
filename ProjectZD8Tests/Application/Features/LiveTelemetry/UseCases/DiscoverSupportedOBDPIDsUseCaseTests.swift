import Foundation
import XCTest
@testable import ProjectZD8

/// 保存を伴わない対応PID探索 `DiscoverSupportedOBDPIDsUseCase` の標準PID・車種専用PID探索を検証します。
final class DiscoverSupportedOBDPIDsUseCaseTests: XCTestCase {
    /// 固定値の短縮名です。
    private typealias Fixtures = AdapterPIDDiscoveryFixtures

    // MARK: - execute

    /// 型式ありでは対応標準PIDと応答した車種専用PIDをService/PID昇順で返します。
    ///
    /// 責務: 標準と車種専用の探索結果が1つの昇順一覧になることを確認します。
    func testExecuteReturnsStandardAndRespondingVehicleSpecificInAscendingOrder() async throws {
        let telemetry = AdapterPIDTelemetryFake(
            bitmaps: [0x00: Fixtures.bitmap([0x0C, 0x05])],
            vehicleSpecificResponses: [Fixtures.zd8Odometer: [0, 0, 0, 1]]
        )
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.execute(vehicleModelCode: "ZD8", endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.standard(0x05), Fixtures.standard(0x0C), Fixtures.zd8Odometer])
    }

    /// 型式なしでは車種専用PIDを照会せず、標準PIDだけを返します。
    ///
    /// 責務: 型式コードが無い探索が車種専用PIDを対象にしないことを確認します。
    func testExecuteWithoutModelCodeSkipsVehicleSpecificPIDs() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.execute(vehicleModelCode: nil, endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [0x05, 0x0C, 0x0F, 0x11].map(Fixtures.standard))
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    /// カタログが注入されていなければ型式があっても車種専用PIDを照会しません。
    ///
    /// 責務: 定義の読込先が無い探索が標準PIDだけで完了することを確認します。
    func testExecuteWithoutDefinitionRepositorySkipsVehicleSpecificPIDs() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        let result = try await useCase.execute(vehicleModelCode: "ZD8", endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [0x05, 0x0C, 0x0F, 0x11].map(Fixtures.standard))
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    /// 呼ぶたびにアダプターへ問い合わせます。
    ///
    /// 責務: 探索結果を保持せず、2回の実行で2回照会することを確認します。
    func testExecuteQueriesAdapterOnEveryCall() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        _ = try await useCase.execute(vehicleModelCode: "ZD8", endpoint: Fixtures.endpoint)
        _ = try await useCase.execute(vehicleModelCode: "ZD8", endpoint: Fixtures.endpoint)

        XCTAssertEqual(telemetry.discoveryCount, 2)
        XCTAssertEqual(telemetry.vehicleSpecificQueries.count, 2)
    }

    /// 標準PIDの探索失敗はそのまま投げ、車種専用PIDを照会しません。
    ///
    /// 責務: アダプター通信の失敗が空の探索結果へ潰されないことを確認します。
    func testExecutePropagatesStandardDiscoveryFailure() async {
        let telemetry = Fixtures.adapter(bitmapFailure: AdapterPIDDiscoveryTestError.adapterFailed)
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        await assertThrows(AdapterPIDDiscoveryTestError.adapterFailed) {
            _ = try await useCase.execute(vehicleModelCode: "ZD8", endpoint: Fixtures.endpoint)
        }
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    // MARK: - discoverStandard

    /// 継続ビットに従って次範囲へ進み、範囲照会PID自体は結果へ含めません。
    ///
    /// 責務: 00→20の照会連鎖と範囲PID除外を確認します。
    func testDiscoverStandardFollowsContinuationBitAndExcludesRangePIDs() async throws {
        let telemetry = AdapterPIDTelemetryFake(bitmaps: [
            0x00: Fixtures.bitmap([0x01], continues: true),
            0x20: Fixtures.bitmap([0x21], base: 0x20)
        ])
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        let result = try await useCase.discoverStandard(using: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.standard(0x01), Fixtures.standard(0x21)])
        XCTAssertEqual(telemetry.bitmapQueries, [0x00, 0x20])
    }

    /// 継続ビットが無ければ最初の範囲だけを照会します。
    ///
    /// 責務: 継続ビットなしの応答で照会連鎖が止まることを確認します。
    func testDiscoverStandardStopsWithoutContinuationBit() async throws {
        let telemetry = AdapterPIDTelemetryFake(bitmaps: [
            0x00: Fixtures.bitmap([0x1F]),
            0x20: Fixtures.bitmap([0x21], base: 0x20)
        ])
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        let result = try await useCase.discoverStandard(using: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.standard(0x1F)])
        XCTAssertEqual(telemetry.bitmapQueries, [0x00])
    }

    /// 継続ビットが立ち続けてもE0範囲で照会を止め、FFを上限に結果へ含めます。
    ///
    /// 責務: 最終範囲E0の境界でPID番号があふれないことを確認します。
    func testDiscoverStandardStopsAtE0RangeAndKeepsFF() async throws {
        let bases: [UInt8] = [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0]
        var bitmaps = Dictionary(uniqueKeysWithValues: bases.map { ($0, Fixtures.bitmap([], base: $0, continues: true)) })
        bitmaps[0xE0] = Fixtures.bitmap([0xFF], base: 0xE0, continues: true)
        let telemetry = AdapterPIDTelemetryFake(bitmaps: bitmaps)
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        let result = try await useCase.discoverStandard(using: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.standard(0xFF)])
        XCTAssertEqual(telemetry.bitmapQueries, bases)
    }

    /// 4バイト未満の対応ビットマップは無応答として失敗します。
    ///
    /// 責務: 短い応答が空の対応一覧へ潰されないことを確認します。
    func testDiscoverStandardThrowsNoVehicleResponseForShortBitmap() async {
        let telemetry = AdapterPIDTelemetryFake(bitmaps: [0x00: [0xFF, 0xFF, 0xFF]])
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        await assertThrows(OBDPIDTelemetryError.noVehicleResponse) {
            _ = try await useCase.discoverStandard(using: Fixtures.endpoint)
        }
    }

    /// ちょうど4バイトの対応ビットマップは受け付けます。
    ///
    /// 責務: 応答長の下限境界が成功側に含まれることを確認します。
    func testDiscoverStandardAcceptsExactlyFourBytes() async throws {
        let telemetry = AdapterPIDTelemetryFake(bitmaps: [0x00: Fixtures.bitmap([0x01])])
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        let result = try await useCase.discoverStandard(using: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.standard(0x01)])
    }

    /// 範囲照会への応答が無ければ無応答として失敗します。
    ///
    /// 責務: 応答欠落が空の対応一覧へ潰されないことを確認します。
    func testDiscoverStandardThrowsNoVehicleResponseWhenRangeIsUnanswered() async {
        let telemetry = AdapterPIDTelemetryFake(bitmaps: [:])
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry)

        await assertThrows(OBDPIDTelemetryError.noVehicleResponse) {
            _ = try await useCase.discoverStandard(using: Fixtures.endpoint)
        }
    }

    // MARK: - discoverVehicleSpecific

    /// 型式は大文字小文字を区別せず照合し、応答したPIDだけを返します。
    ///
    /// 責務: 型式一致の専用PIDだけを照会し、無応答PIDを除くことを確認します。
    func testDiscoverVehicleSpecificMatchesModelCodeCaseInsensitivelyAndKeepsResponders() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.discoverVehicleSpecific(vehicleModelCode: "zd8", excluding: [], endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [Fixtures.zd8Odometer])
        XCTAssertEqual(telemetry.vehicleSpecificQueries.map(Set.init), [[Fixtures.zd8Odometer, Fixtures.zd8OilTemperature]])
    }

    /// 既に対応確認済みのPIDは再照会しません。
    ///
    /// 責務: `excluding` に含まれるPIDを照会対象から除くことを確認します。
    func testDiscoverVehicleSpecificSkipsExcludedPIDs() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.discoverVehicleSpecific(
            vehicleModelCode: "ZD8",
            excluding: [Fixtures.zd8Odometer],
            endpoint: Fixtures.endpoint
        )

        XCTAssertEqual(result, [])
        XCTAssertEqual(telemetry.vehicleSpecificQueries, [[Fixtures.zd8OilTemperature]])
    }

    /// 型式に一致する定義が無ければアダプターへ照会せず空を返します。
    ///
    /// 責務: 一致定義0件の境界で通信が発生しないことを確認します。
    func testDiscoverVehicleSpecificReturnsEmptyWithoutQueryWhenNoDefinitionMatches() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.discoverVehicleSpecific(vehicleModelCode: "AB1", excluding: [], endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [])
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    /// 別型式の専用PIDは照会対象に含めません。
    ///
    /// 責務: 型式XX9の定義を型式ZD8の照会へ混ぜないことを確認します。
    func testDiscoverVehicleSpecificIgnoresOtherModelDefinitions() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        _ = try await useCase.discoverVehicleSpecific(vehicleModelCode: "ZD8", excluding: [], endpoint: Fixtures.endpoint)

        XCTAssertFalse(telemetry.vehicleSpecificQueries.joined().contains(Fixtures.otherModelPID))
    }

    /// 型式なしでは照会せず空を返します。
    ///
    /// 責務: `vehicleModelCode == nil` の分岐で通信が発生しないことを確認します。
    func testDiscoverVehicleSpecificWithoutModelCodeReturnsEmpty() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        let result = try await useCase.discoverVehicleSpecific(vehicleModelCode: nil, excluding: [], endpoint: Fixtures.endpoint)

        XCTAssertEqual(result, [])
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    /// カタログ読込の失敗はそのまま投げます。
    ///
    /// 責務: 定義読込失敗が空の探索結果へ潰されないことを確認します。
    func testDiscoverVehicleSpecificPropagatesCatalogFailure() async {
        let catalog = FixedPIDDefinitionCatalog(definitions: [], failure: AdapterPIDDiscoveryTestError.catalogFailed)
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: Fixtures.adapter(), definitionRepository: catalog)

        await assertThrows(AdapterPIDDiscoveryTestError.catalogFailed) {
            _ = try await useCase.discoverVehicleSpecific(vehicleModelCode: "ZD8", excluding: [], endpoint: Fixtures.endpoint)
        }
    }

    /// 車種専用PID照会の失敗はそのまま投げます。
    ///
    /// 責務: 専用PID通信の失敗が空の探索結果へ潰されないことを確認します。
    func testDiscoverVehicleSpecificPropagatesTelemetryFailure() async {
        let telemetry = AdapterPIDTelemetryFake(vehicleSpecificFailure: AdapterPIDDiscoveryTestError.adapterFailed)
        let useCase = DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: Fixtures.catalog)

        await assertThrows(AdapterPIDDiscoveryTestError.adapterFailed) {
            _ = try await useCase.discoverVehicleSpecific(vehicleModelCode: "ZD8", excluding: [], endpoint: Fixtures.endpoint)
        }
    }

    /// 非同期処理が指定エラーを投げることを確認します。
    ///
    /// 責務: 成功または別エラーを型とcaseまで比べて失敗として記録します。
    /// - Parameters:
    ///   - expected: 期待するエラー。
    ///   - body: 実行する処理。
    private func assertThrows<E: Error & Equatable>(
        _ expected: E,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("エラーが投げられませんでした: \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expected, "想定外のエラー: \(error)", file: file, line: line)
        }
    }
}
