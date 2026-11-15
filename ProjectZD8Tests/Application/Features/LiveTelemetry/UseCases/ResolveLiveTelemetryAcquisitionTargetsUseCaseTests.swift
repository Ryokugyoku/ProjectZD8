import Foundation
import XCTest
@testable import ProjectZD8

/// `ResolveLiveTelemetryAcquisitionTargetsUseCase` が車両有無に応じて取得対象PIDと対応状況を決めることを検証します。
final class ResolveLiveTelemetryAcquisitionTargetsUseCaseTests: XCTestCase {
    /// 固定値の短縮名です。
    private typealias Fixtures = AdapterPIDDiscoveryFixtures

    // MARK: - 車両なし

    /// 型式なしでは、対応と答えた標準PIDのうちカタログで数値化できるものだけを対象にします。
    ///
    /// 責務: カタログに無いPID・数式なしPID・車種専用PIDが対象に入らないことを確認します。
    func testVehiclelessWithoutModelCodeTargetsSupportedStandardPIDsInCatalog() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = makeUseCase(telemetry: telemetry)

        let targets = try await useCase.execute(request(vehicleID: nil, modelCode: nil))

        XCTAssertEqual(requests(of: targets), [Fixtures.standard(0x05), Fixtures.standard(0x0C)])
        XCTAssertTrue(telemetry.vehicleSpecificQueries.isEmpty)
    }

    /// 型式ありでは、応答した車種専用PIDを対象に足します。
    ///
    /// 責務: 型式一致かつ応答済みの車種専用PIDだけが追加されることを確認します。
    func testVehiclelessWithModelCodeAddsRespondingVehicleSpecificPIDs() async throws {
        let useCase = makeUseCase(telemetry: Fixtures.adapter())

        let targets = try await useCase.execute(request(vehicleID: nil, modelCode: "ZD8"))

        XCTAssertEqual(requests(of: targets), [Fixtures.standard(0x05), Fixtures.standard(0x0C), Fixtures.zd8Odometer])
    }

    /// 対象PIDはすべて対応・収集有効の印を持ちます。
    ///
    /// 責務: 定義ごとに1件ずつ `.supported` かつ収集有効の対応状況が付くことを確認します。
    func testVehiclelessMarksEveryTargetSupportedAndCollectionEnabled() async throws {
        let useCase = makeUseCase(telemetry: Fixtures.adapter())

        let targets = try await useCase.execute(request(vehicleID: nil, modelCode: "ZD8"))

        XCTAssertEqual(targets.capabilities.count, targets.definitions.count)
        XCTAssertEqual(Set(targets.capabilities.map(\.request)), requests(of: targets))
        XCTAssertTrue(targets.capabilities.allSatisfy { $0.support == .supported && $0.isCollectionEnabled })
    }

    /// 車両別対応PIDの保存を読まず、書きません。
    ///
    /// 責務: 車両なしの決定で `VehiclePIDCapabilityRepository` が一度も呼ばれないことを確認します。
    func testVehiclelessNeverTouchesVehicleCapabilityRepository() async throws {
        let repository = VehiclePIDCapabilityRepositorySpy(
            stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([(Fixtures.standard(0x0D), true)])]
        )
        let useCase = makeUseCase(telemetry: Fixtures.adapter(), repository: repository)

        let targets = try await useCase.execute(request(vehicleID: nil, modelCode: "ZD8"))

        XCTAssertEqual(repository.totalCallCount, 0)
        XCTAssertFalse(requests(of: targets).contains(Fixtures.standard(0x0D)))
    }

    /// 開始のたびにアダプターへ問い合わせます。
    ///
    /// 責務: 2回の決定で対応PID探索が2回行われることを確認します。
    func testVehiclelessQueriesAdapterOnEveryExecution() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = makeUseCase(telemetry: telemetry, repository: VehiclePIDCapabilityRepositorySpy())

        _ = try await useCase.execute(request(vehicleID: nil, modelCode: nil))
        _ = try await useCase.execute(request(vehicleID: nil, modelCode: nil))

        XCTAssertEqual(telemetry.discoveryCount, 2)
    }

    /// 探索手段が注入されていなければ `unavailable` を投げ、アダプターへ問い合わせません。
    ///
    /// 責務: 探索手段の欠落が空の取得対象へ潰されないことを確認します。
    func testVehiclelessWithoutDiscoveryThrowsUnavailable() async {
        let telemetry = Fixtures.adapter()
        let useCase = makeUseCase(telemetry: telemetry, repository: VehiclePIDCapabilityRepositorySpy(), injectsDiscovery: false)

        await assertThrows(OBDPIDTelemetryError.unavailable) {
            _ = try await useCase.execute(self.request(vehicleID: nil, modelCode: nil))
        }
        XCTAssertTrue(telemetry.bitmapQueries.isEmpty)
    }

    /// アダプターへの探索失敗はそのまま投げます。
    ///
    /// 責務: 探索失敗が空の取得対象へ潰されないことを確認します。
    func testVehiclelessPropagatesDiscoveryFailure() async {
        let useCase = makeUseCase(telemetry: Fixtures.adapter(bitmapFailure: AdapterPIDDiscoveryTestError.adapterFailed))

        await assertThrows(AdapterPIDDiscoveryTestError.adapterFailed) {
            _ = try await useCase.execute(self.request(vehicleID: nil, modelCode: nil))
        }
    }

    /// 対応PIDが0件のとき、車両あり・なしで同じエラーになります。
    ///
    /// 責務: 同じアダプター応答に対し、車両なしの扱いが既存の車両ありの挙動と一致することを確認します。
    func testZeroSupportedPIDsFailsTheSameWithAndWithoutVehicle() async {
        let withVehicle = makeUseCase(telemetry: Fixtures.silentAdapter, repository: VehiclePIDCapabilityRepositorySpy())
        let withoutVehicle = makeUseCase(telemetry: Fixtures.silentAdapter, repository: VehiclePIDCapabilityRepositorySpy())

        let vehicleError = await capturedError { _ = try await withVehicle.execute(self.request(vehicleID: Fixtures.vehicleID, modelCode: nil)) }
        let vehiclelessError = await capturedError { _ = try await withoutVehicle.execute(self.request(vehicleID: nil, modelCode: nil)) }

        XCTAssertEqual(vehicleError as? OBDPIDTelemetryError, .definitionCatalogUnavailable)
        XCTAssertEqual(vehiclelessError as? OBDPIDTelemetryError, vehicleError as? OBDPIDTelemetryError)
    }

    // MARK: - 車両あり

    /// 保存済み対応PIDがあればアダプターへ標準PIDを問い合わせず、収集有効なものだけを対象にします。
    ///
    /// 責務: 車両ありの既存経路が保存値と収集選択を使うことを確認します。
    func testVehicleReusesStoredCapabilitiesWithoutStandardDiscovery() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy(stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([
            (Fixtures.standard(0x0D), true),
            (Fixtures.standard(0x05), false)
        ])])
        let useCase = makeUseCase(telemetry: telemetry, repository: repository)

        let targets = try await useCase.execute(request(vehicleID: Fixtures.vehicleID, modelCode: nil))

        XCTAssertEqual(requests(of: targets), [Fixtures.standard(0x0D)])
        XCTAssertEqual(targets.capabilities.map(\.isCollectionEnabled), [true])
        XCTAssertTrue(telemetry.bitmapQueries.isEmpty)
        XCTAssertEqual(repository.readVehicleIDs, [Fixtures.vehicleID])
    }

    /// 保存済み対応PIDが無ければ探索して車両へ保存し、カタログにあるものを対象にします。
    ///
    /// 責務: 探索処理の移設後も初回探索と保存の結果が変わらないことを確認します。
    func testVehicleDiscoversAndPersistsWhenNothingStored() async throws {
        let telemetry = Fixtures.adapter()
        let repository = VehiclePIDCapabilityRepositorySpy()
        let useCase = makeUseCase(telemetry: telemetry, repository: repository)

        let targets = try await useCase.execute(request(vehicleID: Fixtures.vehicleID, modelCode: nil))

        XCTAssertEqual(telemetry.discoveryCount, 1)
        XCTAssertEqual(repository.insertedInitial.map { Set($0.map(\.id.request)) }, [Set([0x05, 0x0C, 0x0F, 0x11].map(Fixtures.standard))])
        XCTAssertTrue(repository.insertedInitial.joined().allSatisfy { $0.isCollectionEnabled && $0.id.vehicleID == Fixtures.vehicleID })
        XCTAssertEqual(requests(of: targets), [Fixtures.standard(0x05), Fixtures.standard(0x0C)])
        XCTAssertTrue(targets.capabilities.allSatisfy { $0.support == .supported && $0.isCollectionEnabled })
    }

    /// 型式ありでは応答した車種専用PIDを車両へ追加保存し、対象に含めます。
    ///
    /// 責務: 保存済みの車両でも車種専用PIDの追加探索が従来どおり行われることを確認します。
    func testVehicleWithModelCodeMergesRespondingVehicleSpecificPID() async throws {
        let repository = VehiclePIDCapabilityRepositorySpy(
            stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([(Fixtures.standard(0x0C), true)])]
        )
        let useCase = makeUseCase(telemetry: Fixtures.adapter(), repository: repository)

        let targets = try await useCase.execute(request(vehicleID: Fixtures.vehicleID, modelCode: "ZD8"))

        XCTAssertEqual(repository.merged.map { $0.map(\.id.request) }, [[Fixtures.zd8Odometer]])
        XCTAssertEqual(requests(of: targets), [Fixtures.standard(0x0C), Fixtures.zd8Odometer])
    }

    /// 車両別対応PIDのユースケースが無ければ、数値化できる全定義を対応状況なしで対象にします。
    ///
    /// 責務: 車両ありで対応PID保存が無い既存経路の結果が変わらないことを確認します。
    func testVehicleWithoutCapabilityUseCaseTargetsAllDecodableDefinitionsWithoutCapabilities() async throws {
        let telemetry = Fixtures.adapter()
        let useCase = makeUseCase(telemetry: telemetry)

        let targets = try await useCase.execute(request(vehicleID: Fixtures.vehicleID, modelCode: "ZD8"))

        // fixture のカタログで数値化できるのは、標準 05/0C/0D(0F は数式なし)、ZD8 シードの 21/02・21/17、XX9 専用の 22/01 です。
        let zd8Seed = Set(ZD8OBDPIDSeed.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) })
        XCTAssertEqual(zd8Seed, [Fixtures.zd8Odometer, OBDPIDRequest(service: 0x21, pid: 0x17)], "fixture の前提(ZD8 シードの内容)")
        let decodable: Set<OBDPIDRequest> = [
            Fixtures.standard(0x05), Fixtures.standard(0x0C), Fixtures.standard(0x0D),
            Fixtures.zd8Odometer, OBDPIDRequest(service: 0x21, pid: 0x17), OBDPIDRequest(service: 0x22, pid: 0x01),
        ]
        XCTAssertEqual(requests(of: targets), decodable)
        XCTAssertTrue(targets.capabilities.isEmpty)
        XCTAssertTrue(telemetry.bitmapQueries.isEmpty)
    }

    // MARK: - Helpers

    /// 検証対象を組み立てます。
    ///
    /// 責務: 同じアダプターとカタログを共有する定義読込・車両別対応PID・保存なし探索を1つへまとめます。
    /// - Parameters:
    ///   - telemetry: アダプターのフェイク。
    ///   - repository: 車両別対応PIDの保存先。`nil` の場合は車両別対応PIDのユースケースを注入しません。
    ///   - injectsDiscovery: `false` の場合は保存なし探索を注入しません。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(
        telemetry: AdapterPIDTelemetryFake,
        repository: VehiclePIDCapabilityRepositorySpy? = nil,
        injectsDiscovery: Bool = true
    ) -> ResolveLiveTelemetryAcquisitionTargetsUseCase {
        let catalog = Fixtures.catalog
        return ResolveLiveTelemetryAcquisitionTargetsUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: catalog, telemetry: telemetry),
            loadVehicleCapabilities: repository.map {
                LoadVehiclePIDCapabilitiesUseCase(repository: $0, telemetry: telemetry, definitionRepository: catalog)
            },
            discoverSupportedPIDs: injectsDiscovery
                ? DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: catalog)
                : nil
        )
    }

    /// テスト用の開始要求を返します。
    ///
    /// 責務: 車両IDと型式だけを変えた開始要求を作ります。
    /// - Parameters:
    ///   - vehicleID: 登録車両ID。車両なしは `nil`。
    ///   - modelCode: 型式コード。
    /// - Returns: 固定終端の開始要求。
    private func request(vehicleID: VehicleID?, modelCode: String?) -> LiveTelemetryStartRequest {
        LiveTelemetryStartRequest(endpoint: Fixtures.endpoint, vehicleID: vehicleID, vehicleModelCode: modelCode)
    }

    /// 取得対象定義のService/PID集合を返します。
    ///
    /// 責務: 順序に依存しない比較のため定義一覧を集合へ変換します。
    /// - Parameter targets: 取得対象。
    /// - Returns: 定義のService/PID集合。
    private func requests(of targets: LiveTelemetryAcquisitionTargets) -> Set<OBDPIDRequest> {
        Set(targets.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) })
    }

    /// 非同期処理が投げたエラーを返します。
    ///
    /// 責務: 成功した場合は失敗として記録し、投げられたエラーを比較用に取り出します。
    /// - Parameter body: 実行する処理。
    /// - Returns: 投げられたエラー。成功した場合は `nil`。
    private func capturedError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async -> (any Error)? {
        do {
            try await body()
            XCTFail("エラーが投げられませんでした", file: file, line: line)
            return nil
        } catch {
            return error
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
        let error = await capturedError(file: file, line: line, body)
        XCTAssertEqual(error as? E, expected, "想定外のエラー: \(String(describing: error))", file: file, line: line)
    }
}
