import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループの周回ごとの要求列、初回周回での対象確定、収集トグルの反映を検証します。
@MainActor
final class LiveTelemetryAcquisitionLoopRoundTests: XCTestCase {
    /// 高優先として毎周回要求されるPIDです(service 0x01)。
    private static let highPriorityPIDs: [UInt8] = [0x04, 0x0C, 0x0D, 0x11]
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 高優先4件は毎周回、他は周回番号が8の倍数の時だけ要求され、初回周回で応答しなかったPIDは以後要求されません。
    ///
    /// 責務: 周回0〜16の要求列と、記録へ渡すbatch番号・周回番号・要求列を仕様から組み立てた期待値と照合します。
    func testHighPriorityEveryRoundOthersEveryEighthRoundAndSilentPIDDropped() async {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11]))
        let expectedRounds = (0...16).map(Self.expectedRound(tick:))
        let silent = LiveTelemetryTestDefinitions.request(0x0F)

        await fixture.telemetry.answer(expectedRounds.joined().count) { request in
            request == silent ? .timedOut : .responded([request.pid])
        }
        await fixture.waitForSentRequests(expectedRounds.joined().count + 1)

        let firstOfNextRound = LiveTelemetryTestDefinitions.request(0x04)
        XCTAssertEqual(fixture.telemetry.sentRequests, Array(expectedRounds.joined()) + [firstOfNextRound])
        XCTAssertEqual(fixture.telemetry.sentRequests.filter { $0 == silent }.count, 1)
        let rounds = await fixture.recorder?.roundInputs ?? []
        XCTAssertEqual(rounds.map(\.batchOrdinal), Array(0...17))
        XCTAssertEqual(rounds.map(\.policyTick), Array(0...17))
        XCTAssertEqual(rounds.prefix(17).map(\.requests), expectedRounds)
        let confirmed = collector.confirmedTargets.map { $0.map(LiveTelemetryTestDefinitions.request) }
        XCTAssertEqual(confirmed, [(Self.highPriorityPIDs + [0x05]).map(LiveTelemetryTestDefinitions.request)])
    }

    /// 収集トグルを切ったPIDは、取得準備からループまで通しても一度も要求されません。
    ///
    /// 責務: 保存済みcapabilityで収集無効のPIDが、要求・記録開始入力のどちらにも現れないことを確認します。
    func testCollectionDisabledPIDIsNeverRequestedThroughPreparationAndLoop() async throws {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C, 0x0D, 0x0F])
        let disabled = LiveTelemetryTestDefinitions.request(0x05)
        let prepare = PrepareLiveTelemetryAcquisitionUseCase(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog),
                telemetry: fixture.telemetry
            ),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: StubVehiclePIDCapabilityRepository(
                    capabilities: catalog.map { StubVehiclePIDCapabilityRepository.capability($0, enabled: $0.pid != 0x05) }
                ),
                telemetry: fixture.telemetry
            )
        )
        let prepared = try await prepare.execute(
            vehicleID: LiveTelemetryTestDefinitions.vehicleID,
            vehicleModelCode: nil,
            endpoint: LiveTelemetryTestDefinitions.endpoint
        )

        _ = await fixture.start(definitions: prepared.definitions, capabilities: prepared.capabilities)
        await fixture.telemetry.answer(3 + 2 * 8) { .responded([$0.pid]) }
        await fixture.waitForSentRequests(3 + 2 * 8 + 1)

        XCTAssertFalse(fixture.telemetry.sentRequests.contains(disabled))
        XCTAssertEqual(fixture.telemetry.sentRequests.filter { $0 == LiveTelemetryTestDefinitions.request(0x0F) }.count, 2)
        let startInput = await fixture.recorder?.startInputs.first
        XCTAssertEqual(startInput?.definitions.map(LiveTelemetryTestDefinitions.request).contains(disabled), false)
        XCTAssertEqual(startInput?.capabilities.map(\.request).contains(disabled), false)
        XCTAssertEqual(startInput?.orderedRequests.contains(disabled), false)
    }

    /// 仕様から周回番号ごとの要求列を組み立てます。
    ///
    /// 責務: 周回0は全件、8の倍数は高優先と応答済みの通常PID、それ以外は高優先だけを返します。
    /// - Parameter tick: 周回番号。
    /// - Returns: 周回で送られるべき要求列。
    private static func expectedRound(tick: Int) -> [OBDPIDRequest] {
        let high = highPriorityPIDs.map(LiveTelemetryTestDefinitions.request)
        if tick == 0 { return high + [0x05, 0x0F].map(LiveTelemetryTestDefinitions.request) }
        if tick % 8 == 0 { return high + [LiveTelemetryTestDefinitions.request(0x05)] }
        return high
    }
}
