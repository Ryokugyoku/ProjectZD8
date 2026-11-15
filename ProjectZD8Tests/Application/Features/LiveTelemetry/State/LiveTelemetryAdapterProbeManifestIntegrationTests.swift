import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryAction.startRequested` のアダプター判定結果が、表示モデル → 取得ループ → 実際の取得記録 → メモリ上のGRDBの
/// manifest まで届くことを、未登録車両の取得(常駐リンクで未登録車両を記録する経路)で検証します。
@MainActor
final class LiveTelemetryAdapterProbeManifestIntegrationTests: XCTestCase {
    /// 取得記録とGRDBの部品です。
    private var storage: ConnectionSessionAcquisitionRecorderFixture?
    /// 取得ループです。
    private var loop: LiveTelemetryAcquisitionLoop?
    /// 期限待ちのフェイクです。
    private let deadlineWaiter = ControlledDeadlineWaiterFake()

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに取得Taskを残さないよう上限付きで停止します。
    override func tearDown() async throws {
        if let loop {
            _ = await LiveTelemetryBoundedWaiter.value("取得ループの停止") { await loop.stop() }
        }
        deadlineWaiter.releaseAll()
        loop = nil
        storage = nil
        try await super.tearDown()
    }

    /// ATMA判定ありの結果で始めると、保存されたmanifestに同じ判定結果が入ります。
    ///
    /// 責務: 判定結果が途中で落ちずに保存先まで届くことを確認します。
    func testProbeWithATMAReachesStoredManifest() async throws {
        let probe = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

        let manifest = try await storedManifest(startingWith: probe)

        XCTAssertEqual(manifest?.adapterProbeEvidence, probe)
    }

    /// チップ種別だけの判定結果で始めると、保存されたmanifestのATMA結果は `nil` のままです。
    ///
    /// 責務: ATMA未試行を別の値で補完しないことを確認します。
    func testChipOnlyProbeReachesStoredManifest() async throws {
        let probe = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Genuine, monitorProbeOutcome: nil)

        let manifest = try await storedManifest(startingWith: probe)

        XCTAssertEqual(manifest?.adapterProbeEvidence, probe)
    }

    /// 判定結果なしで始めると、保存されたmanifestの判定結果は `nil` です。
    ///
    /// 責務: 判定なしが保存先で別の値に補完されないことを確認します。
    func testNoProbeStoresNilProbe() async throws {
        let manifest = try await storedManifest(startingWith: nil)

        XCTAssertNotNil(manifest)
        XCTAssertNil(manifest?.adapterProbeEvidence)
    }

    /// ECUが対応を返したPIDだけがmanifestに入り、PID定義のsnapshotと要求順が同じPIDを指し、すべて対応・収集有効です。
    ///
    /// 責務: カタログの 0C/0D のうち 0D だけに対応した未登録車両で、対応外の 0C が定義にも要求順にも入らないことを確認します。
    func testManifestDefinitionsAndOrderCoverOnlySupportedEnabledPIDs() async throws {
        let manifest = try await storedManifest(startingWith: nil, supporting: [0x0D])

        let expected = [LiveTelemetryTestDefinitions.request(0x0D)]
        XCTAssertEqual(manifest?.pidDefinitions.map(\.request), expected)
        XCTAssertEqual(manifest?.orderedRequestedPIDs?.requests, expected)
        XCTAssertEqual(manifest?.pidDefinitions.map(\.capabilitySupport), [.supported])
        XCTAssertEqual(manifest?.pidDefinitions.map(\.isCollectionEnabled), [true])
    }

    // MARK: - Helpers

    /// 未登録車両の取得を指定の判定結果で始め、保存されたmanifestを返します。
    ///
    /// 責務: 表示モデル・取得ループ・実際の取得記録を組み、対応PID探索に応答してmanifestの保存を上限付きで待ちます。
    /// - Parameters:
    ///   - probe: 開始要求に付けるアダプター判定結果。
    ///   - supporting: ECUが対応を返す標準PID。
    /// - Returns: 保存されたmanifest。上限内に保存されなければ `nil`。
    /// - Throws: 部品の生成失敗。
    private func storedManifest(
        startingWith probe: AcquisitionAdapterProbeEvidence?,
        supporting: [UInt8] = [0x0C, 0x0D]
    ) async throws -> ConnectionSessionAcquisitionManifest? {
        let storage = try ConnectionSessionAcquisitionRecorderFixture(storage: .grdb)
        self.storage = storage
        let telemetry = GatedOBDPIDTelemetryFake()
        let model = makeModel(telemetry: telemetry, recorder: storage.recorder)

        model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered, adapterProbeEvidence: probe))
        await telemetry.release(.responded(BitmapOBDPIDTelemetryFake.bitmap(supporting: supporting, base: 0x00, continues: false)))
        let saved = await LiveTelemetryBoundedWaiter.waitUntil("manifestの保存") {
            (try? storage.acquisition.manifest(for: storage.sessionID)) != nil
        }
        guard saved else { return nil }
        let manifest = try storage.acquisition.manifest(for: storage.sessionID)
        XCTAssertEqual(manifest.orderedRequestedPIDs.map { Set($0.requests) }, Set(supporting.map(LiveTelemetryTestDefinitions.request)))
        return manifest
    }

    /// 実際の取得記録を記録ポートに持つ表示モデルを組み立てます。
    ///
    /// 責務: 取得記録部品と同じ2PIDのカタログ・標準PID探索・手動時計で表示モデルを作ります。
    /// - Parameters:
    ///   - telemetry: 要求を待たせるPID取得境界。
    ///   - recorder: 実際の取得記録。
    /// - Returns: 表示モデル。
    private func makeModel(telemetry: GatedOBDPIDTelemetryFake, recorder: ConnectionSessionAcquisitionRecorder) -> LiveTelemetryModel {
        let clock = ManualMonotonicClock()
        let loop = LiveTelemetryAcquisitionLoop(
            telemetry: telemetry, recorder: recorder, clock: clock,
            linkRecovery: LinkRecoveryPortFake(), deadlineWaiter: deadlineWaiter
        )
        self.loop = loop
        let catalog = StubOBDPIDDefinitionRepository(definitions: ConnectionSessionAcquisitionRecorderFixture.definitions, failsRead: false)
        return LiveTelemetryModel(
            state: LiveTelemetryState(),
            prepareAcquisition: PrepareLiveTelemetryAcquisitionUseCase(
                readMajorPIDs: ReadMajorOBDPIDsUseCase(definitionRepository: catalog, telemetry: telemetry),
                loadVehicleCapabilities: nil,
                discoverSupportedStandardPIDs: DiscoverSupportedStandardPIDsUseCase(telemetry: telemetry)
            ),
            acquisitionLoop: loop,
            clock: clock
        )
    }
}
