import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` の再接続上限と探索待機上限を検証します(受け入れ条件11)。
@MainActor
final class BLEAdapterLinkRetryLimitTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness

    /// 上限ちょうどの回数までは再試行し、上限を超えたら connect を呼ばず `retryLimitExceeded` で止まります。
    ///
    /// 責務: 上限2で失敗1・2回目は再接続し、3回目で終端になり以後のイベントでもconnectしないことを確認します。
    func testReconnectsUpToLimitThenStopsWithRetryLimitExceeded() {
        let harness = Harness(maximumConsecutiveReconnects: 2)
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()

        for failure in 1...2 {
            harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: "failure \(failure)"))
            XCTAssertEqual(harness.central.connectCallCount, 1 + failure, "上限以内の失敗\(failure)回目は再接続します")
            XCTAssertEqual(harness.link.state, .connecting)
        }
        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: "failure 3"))

        XCTAssertEqual(harness.central.connectCallCount, 3)
        XCTAssertEqual(harness.link.state, .disconnected(.retryLimitExceeded))
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))
        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: nil))
        harness.central.setPowerState(.poweredOn)
        XCTAssertEqual(harness.central.connectCallCount, 3)
        XCTAssertEqual(harness.link.state, .disconnected(.retryLimitExceeded))
    }

    /// 上限0では最初の失敗で再接続せず `retryLimitExceeded` になります。
    ///
    /// 責務: 再試行を許さない上限の境界で、connectが初回の1回だけであることを確認します。
    func testZeroLimitStopsAtFirstFailure() {
        let harness = Harness(maximumConsecutiveReconnects: 0)
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()

        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: nil))

        XCTAssertEqual(harness.central.connectCallCount, 1)
        XCTAssertEqual(harness.link.state, .disconnected(.retryLimitExceeded))
    }

    /// `ready` に到達すると連続失敗数が戻ります。
    ///
    /// 責務: 上限1で失敗1回の後に `ready` になれば、次の切断でもまだ再接続することを確認します。
    func testReachingReadyResetsConsecutiveFailures() {
        let harness = Harness(maximumConsecutiveReconnects: 1)
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: nil))
        XCTAssertEqual(harness.link.state, .connecting)
        harness.emitConnected()
        harness.emitFFF0Discovery()
        harness.emitNotifyEnabled()
        XCTAssertEqual(harness.link.state, .ready)

        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: "after ready"))

        XCTAssertEqual(harness.central.connectCallCount, 3)
        XCTAssertEqual(harness.link.state, .connecting)
        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: nil))
        XCTAssertEqual(harness.link.state, .disconnected(.retryLimitExceeded))
        XCTAssertEqual(harness.central.connectCallCount, 3)
    }

    /// 探索の待機上限を発火させると接続をキャンセルし `discoveryTimedOut` になり、再試行に数えられます。
    ///
    /// 責務: 注入時間で待機が要求され、発火後の状態・キャンセル・切断後の再接続・回数消費を確認します。
    func testDiscoveryTimeoutCancelsConnectionAndCountsAsRetry() async throws {
        let harness = Harness(maximumConsecutiveReconnects: 1)
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        try await BLEBoundedWaiter.waitUntil("discovery deadline armed") { harness.sleepController.activeIndices.count == 1 }
        XCTAssertEqual(harness.sleepController.requestedDurations.first, Harness.discoveryStepTimeout)

        harness.sleepController.fire(try XCTUnwrap(harness.sleepController.activeIndices.first))
        try await BLEBoundedWaiter.waitUntil("discovery timed out") { harness.states.contains(.disconnected(.discoveryTimedOut)) }

        XCTAssertEqual(harness.central.calls.last, .cancelConnection(Harness.targetIdentifier))
        harness.peripheral.connectionState = .disconnected
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))
        XCTAssertEqual(harness.central.connectCallCount, 2)
        XCTAssertEqual(harness.link.state, .connecting)
        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: nil))
        XCTAssertEqual(harness.link.state, .disconnected(.retryLimitExceeded), "待機上限超過は再試行1回として数える必要があります")
        XCTAssertEqual(harness.central.connectCallCount, 2)
    }

    /// 段階が進んだ後に古い待機が発火しても何も起きません。
    ///
    /// 責務: Service探索の待機を発火させても状態・呼び出しが変わらず、現在の段階の待機だけが有効であることを確認します。
    func testStaleDeadlineAfterStepAdvancedDoesNothing() async throws {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        try await BLEBoundedWaiter.waitUntil("services deadline armed") { harness.sleepController.requestCount >= 1 }
        harness.peripheral.emit(.didDiscoverServices(serviceUUIDs: [BLEUARTCapabilityFixtures.fff0Service], errorDescription: nil))
        try await BLEBoundedWaiter.waitUntil("services deadline replaced") { !harness.sleepController.cancelledIndices.isEmpty }
        let callsBeforeFire = harness.central.calls

        harness.sleepController.cancelledIndices.sorted().forEach { harness.sleepController.fire($0) }
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.link.state, .discovering)
        XCTAssertEqual(harness.central.calls, callsBeforeFire)
        XCTAssertFalse(harness.states.contains(.disconnected(.discoveryTimedOut)))
        try await BLEBoundedWaiter.waitUntil("characteristics deadline armed") { !harness.sleepController.activeIndices.isEmpty }
        harness.sleepController.activeIndices.forEach { harness.sleepController.fire($0) }
        try await BLEBoundedWaiter.waitUntil("current deadline expires") { harness.states.contains(.disconnected(.discoveryTimedOut)) }
    }

    /// `ready` に到達した後に探索中の待機が発火しても何も起きません。
    ///
    /// 責務: 記録された全ての待機を `ready` 後に発火させても `ready` のままで、キャンセルが呼ばれないことを確認します。
    func testDeadlinesFiredAfterReadyDoNothing() async throws {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()
        try await BLEBoundedWaiter.waitUntil("deadlines requested") { harness.sleepController.requestCount >= 1 }
        try await BLEBoundedWaiter.settle()
        let callsBeforeFire = harness.central.calls

        (0..<harness.sleepController.requestCount).forEach { harness.sleepController.fire($0) }
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.link.state, .ready)
        XCTAssertEqual(harness.central.calls, callsBeforeFire)
        XCTAssertEqual(harness.states, [.connecting, .discovering, .ready])
    }
}
