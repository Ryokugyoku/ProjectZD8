import XCTest
@testable import ProjectZD8

/// テレメトリ用トランスポートと監視コマンドが、同じ常駐リンクの受信を同時に取り合わないことを検証します。
@MainActor
final class AdapterLinkOBDCommandTransportContentionTests: XCTestCase {
    /// 処理が終わった順の記録です。
    private final class EventLog {
        /// 終わった処理の名前です(終わった順)。
        var events: [String] = []
    }

    /// 長い占有待ち上限の設定です(縮めた実時間で約2秒)。
    private static let patientLimits = AdapterLinkByteStreamLimits(
        leaseTimeout: .seconds(400),
        linkCheckInterval: .milliseconds(100),
        receiveBufferCapacity: 64 * 1024
    )

    /// テレメトリが使用中の間、監視コマンドは何も送らずに待ち、解放後に実行されます。
    ///
    /// 責務: トランスポートが開いている間は車両確認の送信が0件で、`close()` 後に確認が完了することを確認します。
    func testMonitorCommandWaitsWhileTransportIsOpen() async throws {
        let harness = AdapterLinkByteStreamHarness(limits: Self.patientLimits)
        harness.link.replies = AdapterLinkELMReplyFixtures.initializableAdapter(
            stnIdentity: AdapterLinkELMReplyFixtures.rejected,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        let transport = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await transport.open() }
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: harness.stream)
        let confirmation = Task { @MainActor in try await confirmer.confirmVehicleResponse(timeout: .standard) }
        try await BLEBoundedWaiter.settle(polls: 20)
        XCTAssertTrue(harness.link.writes.isEmpty, "使用中に監視コマンドを送ってはいけない")

        try await AdapterLinkBoundedAwait.value("close") { await transport.close() }
        let outcome = await AdapterLinkBoundedAwait.outcome(of: confirmation, "解放後の車両確認")
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding)
    }

    /// テレメトリが使用を続けると、監視コマンドは上限時間で失敗し、何も送りません。
    ///
    /// 責務: 占有待ちの上限超過が `.leaseUnavailable` になり、リンクへ書き込まないことを確認します。
    func testMonitorCommandFailsAfterLeaseTimeoutWhileTransportStaysOpen() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let transport = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await transport.open() }
        let reader = AdapterLinkVehicleIdentificationNumberReader(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("使用中のVIN読取") { try await reader.readVehicleIdentificationNumber() }
        AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.leaseUnavailable)
        XCTAssertTrue(harness.link.writes.isEmpty)
        XCTAssertEqual(harness.link.state, .ready)
    }

    /// 監視コマンドの実行中、トランスポートの `open()` は監視コマンドが終わるまで待ちます。
    ///
    /// 責務: 車両確認が応答を待つ間は `open()` が完了せず、確認完了の後に完了することを確認します。
    func testTransportOpenWaitsForRunningMonitorCommand() async throws {
        // `0100` の待機上限(30秒)を約1.5秒にして、応答を流す前に期限切れにならないようにします。
        let harness = AdapterLinkByteStreamHarness(limits: Self.patientLimits, timeScale: 20)
        var replies = AdapterLinkELMReplyFixtures.initializableAdapter(
            stnIdentity: AdapterLinkELMReplyFixtures.rejected,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        replies["0100"] = nil
        harness.link.replies = replies
        let log = EventLog()
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: harness.stream)
        let confirmation = Task { @MainActor in
            let result = try await confirmer.confirmVehicleResponse(timeout: .adapterMaximum)
            log.events.append("confirmed")
            return result
        }
        let sentRequest = try await BLEBoundedWaiter.waitUntil("0100 の送信") { harness.link.writtenCommands.contains("0100") }
        guard sentRequest else { return confirmation.cancel() }
        let transport = AdapterLinkOBDCommandTransport(stream: harness.stream)
        let opening = Task { @MainActor in
            try await transport.open()
            log.events.append("opened")
        }
        try await BLEBoundedWaiter.settle(polls: 10)
        XCTAssertTrue(log.events.isEmpty, "監視コマンドの実行中に open が完了してはいけない")

        harness.link.deliver(AdapterLinkELMReplyFixtures.supportedPIDsPositive)
        let confirmed = await AdapterLinkBoundedAwait.outcome(of: confirmation, "確認")
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(confirmed), .responding)
        _ = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: opening, "open"))
        XCTAssertEqual(log.events, ["confirmed", "opened"])
        try await AdapterLinkBoundedAwait.value("close") { await transport.close() }
    }
}
