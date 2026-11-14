import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` の状態復元の引き継ぎを検証します(受け入れ条件6)。
@MainActor
final class BLEAdapterLinkRestorationTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness

    /// 接続済みで一致する復元機器は、電源投入後に retrieve / scan / connect を呼ばず探索へ進みます(start → 復元 → 電源)。
    ///
    /// 責務: 電源投入前は何も呼ばれず、投入後に探索だけが要求され `discovering` になることを確認します。
    func testConnectedRestoredPeripheralAfterStartGoesToDiscoveryWithoutConnecting() {
        let harness = Harness(powerState: .unknown, peripheralState: .connected)
        defer { harness.tearDown() }
        harness.start()
        harness.central.emit(.willRestore([harness.peripheral]))
        assertNothingCalledBeforePowerOn(harness)

        harness.central.setPowerState(.poweredOn)

        assertAdoptedIntoDiscovery(harness)
    }

    /// 復元イベントが `start(preference:)` より先に届いても同じく探索へ進みます(復元 → start → 電源)。
    ///
    /// 責務: start前の復元を保持し、電源投入後に connect なしで `discovering` になることを確認します。
    func testConnectedRestoredPeripheralBeforeStartGoesToDiscoveryWithoutConnecting() {
        let harness = Harness(powerState: .unknown, peripheralState: .connected)
        defer { harness.tearDown() }
        harness.central.emit(.willRestore([harness.peripheral]))
        harness.start()
        assertNothingCalledBeforePowerOn(harness)

        harness.central.setPowerState(.poweredOn)

        assertAdoptedIntoDiscovery(harness)
    }

    /// 復元が先に届き、start時点で既に電源が入っていても探索へ進みます(復元 → 電源 → start)。
    ///
    /// 責務: start前の復元を保持し、startだけで connect なしに `discovering` になることを確認します。
    func testConnectedRestoredPeripheralBeforeStartWhilePoweredOnGoesToDiscovery() {
        let harness = Harness(powerState: .poweredOn, peripheralState: .connected)
        defer { harness.tearDown() }
        harness.central.emit(.willRestore([harness.peripheral]))

        harness.start()

        assertAdoptedIntoDiscovery(harness)
    }

    /// 未接続で一致する復元機器は、電源投入後に connect へ進みます。
    ///
    /// 責務: 電源投入前は何も呼ばれず、投入後にスキャンせずその機器へ connect して `connecting` になることを確認します。
    func testDisconnectedRestoredPeripheralIsConnectedAfterPowerOn() {
        let harness = Harness(powerState: .unknown, peripheralState: .disconnected)
        defer { harness.tearDown() }
        harness.central.emit(.willRestore([harness.peripheral]))
        harness.start()
        assertNothingCalledBeforePowerOn(harness)

        harness.central.setPowerState(.poweredOn)

        XCTAssertEqual(harness.central.calls.last, .connect(Harness.targetIdentifier))
        XCTAssertEqual(harness.central.connectCallCount, 1)
        XCTAssertFalse(harness.central.calls.contains { if case .scanForPeripherals = $0 { true } else { false } })
        XCTAssertTrue(harness.peripheral.calls.isEmpty)
        XCTAssertEqual(harness.link.state, .connecting)
    }

    /// 識別子が一致しない復元機器は無視し、その機器に対して何も呼びません。
    ///
    /// 責務: 復元・電源投入の後も別機器への呼び出しがなく、中央役もその機器へ connect / cancel しないことを確認します。
    func testRestoredPeripheralWithOtherIdentifierIsIgnored() {
        let harness = Harness(powerState: .unknown)
        defer { harness.tearDown() }
        let other = BLEPeripheralRoleFake(identifier: Harness.otherIdentifier, connectionState: .connected)
        harness.start()
        harness.central.emit(.willRestore([other]))

        harness.central.setPowerState(.poweredOn)

        XCTAssertTrue(other.calls.isEmpty)
        XCTAssertFalse(harness.central.calls.contains(.connect(Harness.otherIdentifier)))
        XCTAssertFalse(harness.central.calls.contains(.cancelConnection(Harness.otherIdentifier)))
        XCTAssertNotEqual(harness.link.state, .discovering)
        XCTAssertFalse(harness.states.contains(.discovering))
    }

    /// 電源投入前に中央役・ペリフェラル役のどちらも呼ばれていないことを確認します。
    ///
    /// 責務: connect・探索を含む全呼び出しが空で、探索へ進んでいないことを確認します。
    /// - Parameter harness: 確認するリンクの準備。
    private func assertNothingCalledBeforePowerOn(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(harness.central.calls, [], file: file, line: line)
        XCTAssertEqual(harness.peripheral.calls, [], file: file, line: line)
        XCTAssertNotEqual(harness.link.state, .discovering, file: file, line: line)
    }

    /// 復元機器が接続なしで探索へ引き継がれたことを確認します。
    ///
    /// 責務: 中央役への retrieve / scan / connect がなく、Service探索が要求され `discovering` であることを確認します。
    /// - Parameter harness: 確認するリンクの準備。
    private func assertAdoptedIntoDiscovery(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let forbidden = harness.central.calls.filter {
            switch $0 {
            case .retrievePeripherals, .scanForPeripherals, .connect: true
            case .stopScan, .cancelConnection: false
            }
        }
        XCTAssertEqual(forbidden, [], file: file, line: line)
        guard case .discoverServices = harness.peripheral.calls.first else {
            return XCTFail("復元した接続済み機器は探索へ進む必要があります: \(harness.peripheral.calls)", file: file, line: line)
        }
        XCTAssertEqual(harness.link.state, .discovering, file: file, line: line)
    }
}
