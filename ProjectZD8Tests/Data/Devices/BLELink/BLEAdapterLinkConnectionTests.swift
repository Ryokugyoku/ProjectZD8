import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` の取得・スキャン・接続・再接続の手順と状態遷移列を検証します(受け入れ条件1・2・5・13)。
@MainActor
final class BLEAdapterLinkConnectionTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness

    /// 条件1: 取得で見つかればスキャンせず retrieve → connect の順に呼び `connecting` になります。
    ///
    /// 責務: 呼び出し順・retrieveへ渡す識別子・スキャンしないこと・状態を確認します。
    func testStartWithRetrievablePeripheralRetrievesThenConnectsWithoutScanning() {
        let harness = Harness()
        defer { harness.tearDown() }

        harness.startConnectingViaRetrieve()

        XCTAssertEqual(harness.central.calls, [
            .retrievePeripherals([Harness.targetIdentifier]),
            .connect(Harness.targetIdentifier)
        ])
        XCTAssertEqual(harness.link.state, .connecting)
        XCTAssertEqual(harness.states, [.connecting])
    }

    /// 条件2: 取得が空の時だけスキャンを始め、既知UART Service UUID集合を指定します。
    ///
    /// 責務: retrieve後にスキャンが始まり `awaitingPeripheral` になり、指定Serviceが既知集合と一致することを確認します。
    func testStartWithoutRetrievablePeripheralScansForSupportedServices() throws {
        let harness = Harness()
        defer { harness.tearDown() }

        harness.start()

        XCTAssertEqual(harness.central.calls.count, 2)
        XCTAssertEqual(harness.central.calls.first, .retrievePeripherals([Harness.targetIdentifier]))
        guard case .scanForPeripherals(let services) = try XCTUnwrap(harness.central.calls.last) else {
            return XCTFail("取得が空ならスキャンを始める必要があります: \(harness.central.calls)")
        }
        let expected = Set(AppleBluetoothUARTProfile.supported.map { $0.serviceUUID.uppercased() })
        XCTAssertEqual(Set(services.map { $0.uppercased() }), expected)
        XCTAssertEqual(harness.link.state, .awaitingPeripheral)
    }

    /// 条件2: 識別子が一致しない発見では接続せず、スキャンも止めません。
    ///
    /// 責務: 別機器の発見後に中央役への呼び出しが増えず、状態が `awaitingPeripheral` のままであることを確認します。
    func testDiscoveryOfOtherPeripheralNeitherConnectsNorStopsScan() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.start()
        let callsBeforeDiscovery = harness.central.calls
        let other = BLEPeripheralRoleFake(identifier: Harness.otherIdentifier)

        harness.central.emit(.didDiscover(other))

        XCTAssertEqual(harness.central.calls, callsBeforeDiscovery)
        XCTAssertEqual(harness.link.state, .awaitingPeripheral)
        XCTAssertTrue(other.calls.isEmpty)
    }

    /// 条件2: 一致する機器を発見したらスキャンを止めてから接続します。
    ///
    /// 責務: 発見後の呼び出しが stopScan → connect の順で、状態が `connecting` になることを確認します。
    func testDiscoveryOfTargetStopsScanThenConnects() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.start()
        harness.central.emit(.didDiscover(BLEPeripheralRoleFake(identifier: Harness.otherIdentifier)))
        let callsBeforeDiscovery = harness.central.calls

        harness.central.emit(.didDiscover(harness.peripheral))

        XCTAssertEqual(Array(harness.central.calls.dropFirst(callsBeforeDiscovery.count)), [
            .stopScan,
            .connect(Harness.targetIdentifier)
        ])
        XCTAssertEqual(harness.link.state, .connecting)
        XCTAssertEqual(harness.states, [.awaitingPeripheral, .connecting])
    }

    /// 条件5: `ready` 後の切断で理由付き `disconnected` を経て再接続します。
    ///
    /// 責務: 切断理由を保持した状態を出し、connectが再度呼ばれて `connecting` になることを確認します。
    func testDisconnectAfterReadyReportsReasonAndReconnects() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()
        XCTAssertEqual(harness.link.state, .ready)

        harness.peripheral.connectionState = .disconnected
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: "link supervision timeout"))

        XCTAssertEqual(harness.central.connectCallCount, 2)
        XCTAssertEqual(harness.central.calls.last, .connect(Harness.targetIdentifier))
        XCTAssertEqual(harness.link.state, .connecting)
        XCTAssertEqual(Array(harness.states.suffix(3)), [
            .ready,
            .disconnected(.peripheralDisconnected(errorDescription: "link supervision timeout")),
            .connecting
        ])
    }

    /// 条件5: 接続失敗イベントでも理由付き `disconnected` を経て再接続します。
    ///
    /// 責務: 接続失敗の理由を保持した状態を出し、connectが再度呼ばれて `connecting` になることを確認します。
    func testConnectionFailureReportsReasonAndReconnects() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()

        harness.central.emit(.didFailToConnect(harness.peripheral, errorDescription: "peer removed pairing"))

        XCTAssertEqual(harness.central.connectCallCount, 2)
        XCTAssertEqual(harness.central.calls.last, .connect(Harness.targetIdentifier))
        XCTAssertEqual(harness.link.state, .connecting)
        XCTAssertEqual(harness.states, [
            .connecting,
            .disconnected(.connectionFailed(errorDescription: "peer removed pairing")),
            .connecting
        ])
    }

    /// 条件13: 取得→接続→探索→Notify有効化で `connecting` → `discovering` → `ready` の順に届きます。
    ///
    /// 責務: 状態変化ハンドラへ届いた遷移列全体を確認します。
    func testStateHandlerReceivesConnectingDiscoveringReadyInOrder() {
        let harness = Harness()
        defer { harness.tearDown() }

        harness.driveToReady()

        XCTAssertEqual(harness.states, [.connecting, .discovering, .ready])
        XCTAssertEqual(harness.link.state, .ready)
    }

    /// 条件13: スキャン経由の接続から切断・再接続までの遷移列が順に届きます。
    ///
    /// 責務: `awaitingPeripheral` から始まり、切断後の `disconnected` → `connecting` までの遷移列を確認します。
    func testStateHandlerReceivesScanPathAndReconnectTransitionsInOrder() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.start()
        harness.central.emit(.didDiscover(harness.peripheral))
        harness.emitConnected()
        harness.emitFFF0Discovery()
        harness.emitNotifyEnabled()

        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))

        XCTAssertEqual(harness.states, [
            .awaitingPeripheral,
            .connecting,
            .discovering,
            .ready,
            .disconnected(.peripheralDisconnected(errorDescription: nil)),
            .connecting
        ])
    }
}
