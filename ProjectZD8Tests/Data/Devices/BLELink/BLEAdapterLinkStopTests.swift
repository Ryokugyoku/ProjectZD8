import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink.stop()` と終端からのやり直しを検証します(受け入れ条件12)。
@MainActor
final class BLEAdapterLinkStopTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness

    /// スキャン中の `stop()` はスキャンを止めて `idle` になります。
    ///
    /// 責務: スキャン後の呼び出しに stopScan が加わり、状態が `idle` になることを確認します。
    func testStopWhileScanningStopsScanAndBecomesIdle() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.start()
        XCTAssertEqual(harness.link.state, .awaitingPeripheral)

        harness.link.stop()

        XCTAssertEqual(harness.central.calls.last, .stopScan)
        XCTAssertEqual(harness.link.state, .idle)
        XCTAssertEqual(harness.states.last, .idle)
    }

    /// `ready` 中の `stop()` は接続をキャンセルして `idle` になり、以後の切断通知で再接続しません。
    ///
    /// 責務: キャンセル呼び出し・状態と、停止後の切断通知でconnectが増えないことを確認します。
    func testStopWhileReadyCancelsConnectionAndBecomesIdle() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()

        harness.link.stop()

        XCTAssertEqual(harness.central.calls.last, .cancelConnection(BLEAdapterLinkTestHarness.targetIdentifier))
        XCTAssertEqual(harness.link.state, .idle)
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))
        XCTAssertEqual(harness.central.connectCallCount, 1)
        XCTAssertEqual(harness.link.state, .idle)
    }

    /// 接続要求中の `stop()` は保留中の接続要求をキャンセルします。
    ///
    /// 責務: connect後の `stop()` で同じ機器のキャンセルが呼ばれ `idle` になることを確認します。
    func testStopWhileConnectingCancelsPendingConnection() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()

        harness.link.stop()

        XCTAssertEqual(harness.central.calls.last, .cancelConnection(BLEAdapterLinkTestHarness.targetIdentifier))
        XCTAssertEqual(harness.link.state, .idle)
    }

    /// 待機中の `write` は `stop()` で `stopped` エラーになります。
    ///
    /// 責務: 応答待ちで止まっている書き込みが停止で明示的なエラーとして終わることを確認します。
    func testStopFailsPendingWriteWithStopped() async throws {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.peripheral.maximumWriteLengths = [.withResponse: 2, .withoutResponse: 2]
        harness.driveToReady(write: BLEUARTCapabilityFixtures.writeWithResponseFFF2)
        let attempt = harness.beginWrite(Data([1, 2, 3, 4, 5]))
        try await BLEBoundedWaiter.waitUntil("first chunk") { harness.peripheral.writtenChunks.count >= 1 }
        XCTAssertFalse(attempt.isFinished)

        harness.link.stop()
        try await BLEBoundedWaiter.waitUntil("write ends") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .failed(.stopped))
    }

    /// 未知プロファイルの終端から `stop()` → `start(preference:)` でやり直せます。
    ///
    /// 責務: 終端後の停止で `idle` になり、再開始で retrieve → connect が再び呼ばれ `connecting` になることを確認します。
    func testStopThenStartRecoversFromUnknownProfileTerminal() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        harness.peripheral.emit(.didDiscoverServices(serviceUUIDs: [], errorDescription: nil))
        XCTAssertEqual(harness.link.state, .disconnected(.unknownUARTProfile))

        harness.link.stop()
        XCTAssertEqual(harness.link.state, .idle)
        let callsBeforeRestart = harness.central.calls.count
        harness.peripheral.connectionState = .disconnected
        harness.start()

        XCTAssertEqual(Array(harness.central.calls.dropFirst(callsBeforeRestart)), [
            .retrievePeripherals([BLEAdapterLinkTestHarness.targetIdentifier]),
            .connect(BLEAdapterLinkTestHarness.targetIdentifier)
        ])
        XCTAssertEqual(harness.link.state, .connecting)
    }

    /// 再試行上限・不正な識別子の終端からも `stop()` → `start(preference:)` でやり直せます。
    ///
    /// 責務: 各終端の後に停止・再開始すると connect が呼ばれ `connecting` になることを確認します。
    func testStopThenStartRecoversFromRetryLimitAndInvalidIdentifierTerminals() {
        let retryHarness = Harness(maximumConsecutiveReconnects: 0)
        defer { retryHarness.tearDown() }
        retryHarness.startConnectingViaRetrieve()
        retryHarness.central.emit(.didFailToConnect(retryHarness.peripheral, errorDescription: nil))
        XCTAssertEqual(retryHarness.link.state, .disconnected(.retryLimitExceeded))
        retryHarness.link.stop()
        retryHarness.start()
        XCTAssertEqual(retryHarness.central.connectCallCount, 2)
        XCTAssertEqual(retryHarness.link.state, .connecting)

        let invalidHarness = Harness()
        defer { invalidHarness.tearDown() }
        invalidHarness.central.retrieveResult = [invalidHarness.peripheral]
        invalidHarness.start(systemIdentifier: "invalid")
        XCTAssertEqual(invalidHarness.link.state, .disconnected(.invalidIdentifier))
        invalidHarness.link.stop()
        invalidHarness.start()
        XCTAssertEqual(invalidHarness.central.calls, [
            .retrievePeripherals([BLEAdapterLinkTestHarness.targetIdentifier]),
            .connect(BLEAdapterLinkTestHarness.targetIdentifier)
        ])
        XCTAssertEqual(invalidHarness.link.state, .connecting)
    }
}
