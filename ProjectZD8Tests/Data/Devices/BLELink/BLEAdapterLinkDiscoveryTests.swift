import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` の探索・プロファイル解決・Notify有効化と未知プロファイルの終端を検証します(受け入れ条件3・4)。
@MainActor
final class BLEAdapterLinkDiscoveryTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// 条件3: 接続成功で `discovering` になり、Service探索を要求します。
    ///
    /// 責務: 接続成功直後の状態と、最初のペリフェラル呼び出しがService探索であることを確認します。
    func testConnectionSuccessEntersDiscoveringAndDiscoversServices() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()

        harness.emitConnected()

        XCTAssertEqual(harness.link.state, .discovering)
        guard case .discoverServices = harness.peripheral.calls.first else {
            return XCTFail("接続後はService探索を要求する必要があります: \(harness.peripheral.calls)")
        }
        XCTAssertEqual(harness.peripheral.calls.count, 1)
    }

    /// 条件3: FFF0構成に解決できると notify 特性 FFF1 のNotifyを有効化し、完了前は `ready` になりません。
    ///
    /// 責務: Characteristic探索→Notify要求の順序、Notify対象、完了前の状態を確認します。
    func testResolvedFFF0EnablesNotifyOnNotifyCharacteristicAndWaitsForCompletion() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()

        harness.emitFFF0Discovery()

        XCTAssertEqual(Array(harness.peripheral.calls.dropFirst()), [
            .discoverCharacteristics(Fixtures.fff0Service),
            .setNotifyValue(true, characteristicUUID: Fixtures.fff1Notify, serviceUUID: Fixtures.fff0Service)
        ])
        XCTAssertEqual(harness.link.state, .discovering)
        XCTAssertFalse(harness.states.contains(.ready))
    }

    /// 条件3: Notify有効化の完了が届いて初めて `ready` になります。
    ///
    /// 責務: 完了通知の前後で状態が `discovering` → `ready` に変わることを確認します。
    func testNotifyCompletionMakesLinkReady() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        harness.emitFFF0Discovery()
        XCTAssertEqual(harness.link.state, .discovering)

        harness.emitNotifyEnabled()

        XCTAssertEqual(harness.link.state, .ready)
    }

    /// 条件3: 別Characteristicの通知状態更新はNotify有効化の完了として扱いません。
    ///
    /// 責務: notify特性以外の更新では `ready` にならないことを確認します。
    func testNotificationStateOfOtherCharacteristicDoesNotMakeLinkReady() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        harness.emitFFF0Discovery()

        harness.peripheral.emit(.didUpdateNotificationState(characteristicUUID: Fixtures.fff2Write, isNotifying: true, errorDescription: nil))

        XCTAssertEqual(harness.link.state, .discovering)
        XCTAssertFalse(harness.states.contains(.ready))
    }

    /// 条件3: 複数Serviceを発見した時は全ServiceのCharacteristic探索がそろうまでNotifyを有効化しません。
    ///
    /// 責務: 1件目のCharacteristic探索結果だけではNotify要求が出ず、2件目でFFF1へ出ることを確認します。
    func testNotifyIsRequestedOnlyAfterAllServicesReportCharacteristics() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        harness.peripheral.emit(.didDiscoverServices(serviceUUIDs: ["180A", Fixtures.fff0Service], errorDescription: nil))
        harness.peripheral.emit(.didDiscoverCharacteristics(
            serviceUUID: Fixtures.fff0Service,
            capabilities: [Fixtures.notifyFFF1, Fixtures.writeWithoutResponseFFF2],
            errorDescription: nil
        ))
        XCTAssertFalse(harness.peripheral.calls.contains { if case .setNotifyValue = $0 { true } else { false } })

        harness.peripheral.emit(.didDiscoverCharacteristics(serviceUUID: "180A", capabilities: [], errorDescription: nil))

        XCTAssertEqual(
            harness.peripheral.calls.last,
            .setNotifyValue(true, characteristicUUID: Fixtures.fff1Notify, serviceUUID: Fixtures.fff0Service)
        )
        XCTAssertEqual(harness.link.state, .discovering)
    }

    /// 条件4: 既知Serviceがない(Serviceなし)と未知プロファイルの終端になり、再接続しません。
    ///
    /// 責務: Service空の探索結果で `disconnected(.unknownUARTProfile)`、接続キャンセル、connect不再呼び出しを確認します。
    func testNoServicesFailsTerminallyAsUnknownProfile() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()

        harness.peripheral.emit(.didDiscoverServices(serviceUUIDs: [], errorDescription: nil))

        assertTerminatedAsUnknownProfile(harness)
    }

    /// 条件4: 既知でないServiceしかない場合は未知プロファイルの終端になります。
    ///
    /// 責務: 既知UART以外のServiceだけを探索し終えた時の終端と接続キャンセルを確認します。
    func testOnlyUnknownServiceFailsTerminallyAsUnknownProfile() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()
        harness.peripheral.emit(.didDiscoverServices(serviceUUIDs: ["180A"], errorDescription: nil))

        harness.peripheral.emit(.didDiscoverCharacteristics(
            serviceUUID: "180A",
            capabilities: [Fixtures.capability("2A29", notify: true, withResponse: true)],
            errorDescription: nil
        ))

        assertTerminatedAsUnknownProfile(harness)
    }

    /// 条件4: FFF0でもNotify能力がなければ未知プロファイルの終端になります。
    ///
    /// 責務: notify特性がNotify不可の時の終端と接続キャンセルを確認します。
    func testMissingNotifyCapabilityFailsTerminallyAsUnknownProfile() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()

        harness.emitFFF0Discovery(notify: Fixtures.nonNotifyFFF1)

        assertTerminatedAsUnknownProfile(harness)
    }

    /// 条件4: FFF0でもWrite能力がなければ未知プロファイルの終端になります。
    ///
    /// 責務: write特性が書き込み不可の時の終端と接続キャンセルを確認します。
    func testMissingWriteCapabilityFailsTerminallyAsUnknownProfile() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.startConnectingViaRetrieve()
        harness.emitConnected()

        harness.emitFFF0Discovery(write: Fixtures.nonWritableFFF2)

        assertTerminatedAsUnknownProfile(harness)
    }

    /// 未知プロファイルの終端になったことを確認します。
    ///
    /// 責務: 状態・接続キャンセル・Notify未要求と、後続の切断通知でもconnectが再度呼ばれないことを確認します。
    /// - Parameter harness: 確認するリンクの準備。
    private func assertTerminatedAsUnknownProfile(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(harness.link.state, .disconnected(.unknownUARTProfile), file: file, line: line)
        XCTAssertTrue(harness.central.calls.contains(.cancelConnection(Harness.targetIdentifier)), file: file, line: line)
        XCTAssertFalse(harness.states.contains(.ready), file: file, line: line)
        XCTAssertFalse(
            harness.peripheral.calls.contains { if case .setNotifyValue(true, _, _) = $0 { true } else { false } },
            file: file,
            line: line
        )

        harness.peripheral.connectionState = .disconnected
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))

        XCTAssertEqual(harness.central.connectCallCount, 1, file: file, line: line)
        XCTAssertEqual(harness.link.state, .disconnected(.unknownUARTProfile), file: file, line: line)
    }
}
