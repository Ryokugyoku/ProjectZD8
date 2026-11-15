import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 車両なし開始から実際の取得証跡controllerとインメモリGRDBまで通し、保存されたmanifestを検証します。
@MainActor
final class LiveTelemetryVehiclelessManifestIntegrationTests: XCTestCase {
    /// 固定値の短縮名です。
    private typealias Fixtures = AdapterPIDDiscoveryFixtures
    /// ATMA判定ありのアダプター判定結果です。
    private let withATMA = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// 車両なしでもmanifestとPID定義snapshotが作られ、対象PIDは対応・収集有効でアダプター判定結果を持ちます。
    ///
    /// 責務: 車両なし開始の取得証跡が保存先まで欠落なく届くことを確認します。
    func testVehiclelessStartPersistsManifestWithSupportedEnabledSnapshotsAndProbe() async throws {
        let manifest = try await persistedManifest(vehicleID: nil, probe: withATMA)

        XCTAssertEqual(Set(manifest.pidDefinitions.map(\.request)), [Fixtures.standard(0x05), Fixtures.standard(0x0C)])
        XCTAssertTrue(manifest.pidDefinitions.allSatisfy { $0.capabilitySupport == .supported && $0.isCollectionEnabled == true })
        XCTAssertEqual(manifest.adapterProbeEvidence, withATMA)
    }

    /// 同じ対象PIDなら、車両あり・なしで同じ形のmanifestが作られます。
    ///
    /// 責務: 車両なしのPID定義snapshotと要求順が車両ありと一致することを確認します。
    func testVehiclelessManifestHasSameShapeAsVehicleManifest() async throws {
        let chipOnly = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Genuine, monitorProbeOutcome: nil)
        let vehicleless = try await persistedManifest(vehicleID: nil, probe: chipOnly)
        let vehicle = try await persistedManifest(vehicleID: Fixtures.vehicleID, probe: chipOnly)

        XCTAssertEqual(vehicleless.pidDefinitions, vehicle.pidDefinitions)
        XCTAssertEqual(vehicleless.orderedRequestedPIDs, vehicle.orderedRequestedPIDs)
        XCTAssertEqual(vehicleless.adapterProbeEvidence, chipOnly)
        XCTAssertEqual(vehicle.adapterProbeEvidence, chipOnly)
    }

    /// 判定結果を付けない開始では保存されたmanifestの判定結果も `nil` です。
    ///
    /// 責務: 判定なしが保存先で別の値に補完されないことを確認します。
    func testStartWithoutProbePersistsNilProbeEvidence() async throws {
        let manifest = try await persistedManifest(vehicleID: nil, probe: nil)

        XCTAssertNil(manifest.adapterProbeEvidence)
    }

    // MARK: - Helpers

    /// 指定条件で取得を開始し、保存されたmanifestを返します。
    ///
    /// 責務: インメモリGRDB・実controller・アダプターのフェイクを組み、上限付きでmanifest保存を待ってから停止します。
    /// - Parameters:
    ///   - vehicleID: 登録車両ID。車両なしは `nil`。車両ありの場合は 05/0C を収集有効で保存済みにします。
    ///   - probe: 開始要求に付けるアダプター判定結果。
    /// - Returns: 保存先から読み戻したmanifest。
    private func persistedManifest(
        vehicleID: VehicleID?,
        probe: AcquisitionAdapterProbeEvidence?
    ) async throws -> ConnectionSessionAcquisitionManifest {
        let queue = try DatabaseQueue()
        let storage = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let session = ConnectionSession(accountIdentifier: "unit2-account", startedAt: Date(timeIntervalSince1970: 1))
        try storage.save(session)
        let model = makeModel(acquisition: acquisition, sessionID: session.id)
        model.send(.startRequested(LiveTelemetryStartRequest(
            endpoint: Fixtures.endpoint,
            vehicleID: vehicleID,
            vehicleModelCode: nil,
            adapterProbeEvidence: probe
        )))
        try await BLEBoundedWaiter.waitUntil("manifest保存") {
            (try? acquisition.manifest(for: session.id)) != nil || model.state.phase == .failed
        }
        XCTAssertNil(model.state.failureKey)
        model.send(.stopRequested)
        try await BLEBoundedWaiter.waitUntil("停止完了") { model.state.phase == .idle || model.state.phase == .failed }
        return try acquisition.manifest(for: session.id)
    }

    /// 実controllerを取得証跡として持つモデルを組み立てます。
    ///
    /// 責務: 同じアダプター・カタログ・保存先を共有する取得経路を1つのモデルへ注入します。
    /// - Parameters:
    ///   - acquisition: 取得証跡の保存先。
    ///   - sessionID: 取得証跡を所有する進行中セッションID。
    /// - Returns: 方式Bの取得証跡を使うモデル。
    private func makeModel(acquisition: GRDBConnectionSessionAcquisitionRepository, sessionID: ConnectionSessionID) -> LiveTelemetryModel {
        let telemetry = Fixtures.adapter()
        let catalog = Fixtures.catalog
        let repository = VehiclePIDCapabilityRepositorySpy(stored: [Fixtures.vehicleID: Fixtures.storedCapabilities([
            (Fixtures.standard(0x05), true),
            (Fixtures.standard(0x0C), true)
        ])])
        let controller = ConnectionSessionAcquisitionController(
            createManifest: CreateConnectionSessionAcquisitionManifestUseCase(
                acquisitionRepository: acquisition,
                evidencePort: FixedRuntimeEvidencePort()
            ),
            persistBatch: PersistAcquisitionBatchUseCase(
                repository: acquisition,
                telemetry: telemetry,
                now: { Date(timeIntervalSince1970: 20) },
                monotonicNanoseconds: { 0 }
            ),
            activeSessionID: { sessionID },
            manifestVersion: 1,
            pollingPolicyVersion: 1,
            modelInputManifestVersion: 1,
            formulaCanonicalizationVersion: 1
        )
        return LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: catalog, telemetry: telemetry),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(repository: repository, telemetry: telemetry, definitionRepository: catalog),
            discoverSupportedPIDs: DiscoverSupportedOBDPIDsUseCase(telemetry: telemetry, definitionRepository: catalog),
            acquisitionEvidence: controller
        )
    }
}
