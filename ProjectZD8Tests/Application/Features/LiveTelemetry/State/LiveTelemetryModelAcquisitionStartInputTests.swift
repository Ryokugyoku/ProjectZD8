import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryModel` が取得証跡へ渡す開始入力(定義・対応状況・アダプター判定結果)を検証します。
@MainActor
final class LiveTelemetryModelAcquisitionStartInputTests: XCTestCase {
    /// 固定値の短縮名です。
    private typealias Fixtures = AdapterPIDDiscoveryFixtures
    /// チップ種別だけのアダプター判定結果です。
    private let chipOnly = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Clone, monitorProbeOutcome: nil)
    /// ATMA判定ありのアダプター判定結果です。
    private let withATMA = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// 車両なしでも取得証跡が開始され、対象PIDはすべて対応・収集有効になります。
    ///
    /// 責務: 車両なしの開始入力で定義ごとに `.supported` かつ収集有効の対応状況が付くことを確認します。
    func testVehiclelessStartInputMarksEveryDefinitionSupportedAndEnabled() async throws {
        let input = try await capturedStartInput(vehicleID: nil, modelCode: "ZD8", probe: nil)

        let definitions = Set(input.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) })
        XCTAssertEqual(definitions, [Fixtures.standard(0x05), Fixtures.standard(0x0C), Fixtures.zd8Odometer])
        XCTAssertEqual(Set(input.capabilities.map(\.request)), definitions)
        XCTAssertEqual(input.capabilities.count, input.definitions.count)
        XCTAssertTrue(input.capabilities.allSatisfy { $0.support == .supported && $0.isCollectionEnabled })
        XCTAssertEqual(Set(input.orderedRequests), definitions)
    }

    /// 車両なしの開始要求に付けたチップ種別だけの判定結果がそのまま渡ります。
    ///
    /// 責務: ATMA未試行の判定結果が欠落せず開始入力へ入ることを確認します。
    func testVehiclelessStartPassesChipOnlyProbeEvidence() async throws {
        let input = try await capturedStartInput(vehicleID: nil, modelCode: nil, probe: chipOnly)

        XCTAssertEqual(input.adapterProbeEvidence, chipOnly)
    }

    /// 車両なしの開始要求に付けたATMA判定ありの結果がそのまま渡ります。
    ///
    /// 責務: チップ種別とATMA結果の両方が開始入力へ入ることを確認します。
    func testVehiclelessStartPassesProbeEvidenceWithATMA() async throws {
        let input = try await capturedStartInput(vehicleID: nil, modelCode: nil, probe: withATMA)

        XCTAssertEqual(input.adapterProbeEvidence, withATMA)
    }

    /// 車両ありの開始要求に付けたチップ種別だけの判定結果がそのまま渡ります。
    ///
    /// 責務: 車両ありでもATMA未試行の判定結果が開始入力へ入ることを確認します。
    func testVehicleStartPassesChipOnlyProbeEvidence() async throws {
        let input = try await capturedStartInput(vehicleID: Fixtures.vehicleID, modelCode: nil, probe: chipOnly)

        XCTAssertEqual(input.adapterProbeEvidence, chipOnly)
    }

    /// 車両ありの開始要求に付けたATMA判定ありの結果がそのまま渡ります。
    ///
    /// 責務: 車両ありでもチップ種別とATMA結果の両方が開始入力へ入ることを確認します。
    func testVehicleStartPassesProbeEvidenceWithATMA() async throws {
        let input = try await capturedStartInput(vehicleID: Fixtures.vehicleID, modelCode: nil, probe: withATMA)

        XCTAssertEqual(input.adapterProbeEvidence, withATMA)
    }

    /// 判定結果を付けない車両なし開始では `nil` が渡ります。
    ///
    /// 責務: 判定なしを別の値で補完しないことを確認します。
    func testVehiclelessStartWithoutProbePassesNil() async throws {
        let input = try await capturedStartInput(vehicleID: nil, modelCode: nil, probe: nil)

        XCTAssertNil(input.adapterProbeEvidence)
    }

    /// 判定結果を付けない車両あり開始では `nil` が渡ります。
    ///
    /// 責務: 車両ありでも判定なしを別の値で補完しないことを確認します。
    func testVehicleStartWithoutProbePassesNil() async throws {
        let input = try await capturedStartInput(vehicleID: Fixtures.vehicleID, modelCode: nil, probe: nil)

        XCTAssertNil(input.adapterProbeEvidence)
    }

    // MARK: - Helpers

    /// 指定条件で取得を開始し、取得証跡へ渡った最初の開始入力を返します。
    ///
    /// 責務: 車両有無・型式・判定結果だけを変えた開始を行い、上限付きで開始入力を待ってから停止します。
    /// - Parameters:
    ///   - vehicleID: 登録車両ID。車両なしは `nil`。
    ///   - modelCode: 型式コード。
    ///   - probe: 開始要求に付けるアダプター判定結果。
    /// - Returns: 取得証跡が受け取った開始入力。
    private func capturedStartInput(
        vehicleID: VehicleID?,
        modelCode: String?,
        probe: AcquisitionAdapterProbeEvidence?
    ) async throws -> LiveTelemetryAcquisitionStartInput {
        let telemetry = Fixtures.adapter()
        let catalog = Fixtures.catalog
        let repository = VehiclePIDCapabilityRepositorySpy(
            stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([(Fixtures.standard(0x0C), true)])]
        )
        let evidence = StartInputRecordingEvidence()
        let model = LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: catalog, telemetry: telemetry),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(repository: repository, telemetry: telemetry, definitionRepository: catalog),
            discoverSupportedPIDs: DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: catalog),
            acquisitionEvidence: evidence
        )
        model.send(.startRequested(LiveTelemetryStartRequest(
            endpoint: Fixtures.endpoint,
            vehicleID: vehicleID,
            vehicleModelCode: modelCode,
            adapterProbeEvidence: probe
        )))
        try await BLEBoundedWaiter.waitUntil("取得証跡の開始") { !evidence.startInputs.isEmpty }
        model.send(.stopRequested)
        try await BLEBoundedWaiter.waitUntil("停止完了") { model.state.phase == .idle || model.state.phase == .failed }
        XCTAssertEqual(evidence.startInputs.count, 1)
        return try XCTUnwrap(evidence.startInputs.first)
    }
}
