import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` のBluetooth利用不可時の扱いと不正な識別子を検証します(受け入れ条件7・8)。
@MainActor
final class BLEAdapterLinkPowerStateTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness

    /// 条件7: poweredOff では何も呼ばず `disconnected(.bluetoothPoweredOff)` になります。
    ///
    /// 責務: 電源オフで開始した時の呼び出しなしと理由を確認します。
    func testPoweredOffCallsNothingAndReportsPoweredOff() {
        assertUnavailablePower(.poweredOff, reports: .bluetoothPoweredOff)
    }

    /// 条件7: unauthorized では何も呼ばず `disconnected(.bluetoothUnauthorized)` になります。
    ///
    /// 責務: 未許可で開始した時の呼び出しなしと理由を確認します。
    func testUnauthorizedCallsNothingAndReportsUnauthorized() {
        assertUnavailablePower(.unauthorized, reports: .bluetoothUnauthorized)
    }

    /// 条件7: unsupported では何も呼ばず `disconnected(.bluetoothUnsupported)` になります。
    ///
    /// 責務: 非対応環境で開始した時の呼び出しなしと理由を確認します。
    func testUnsupportedCallsNothingAndReportsUnsupported() {
        assertUnavailablePower(.unsupported, reports: .bluetoothUnsupported)
    }

    /// 条件7: 3つの利用不可理由は互いに区別できます。
    ///
    /// 責務: poweredOff / unauthorized / unsupported の理由が全て異なる値であることを確認します。
    func testUnavailableReasonsAreDistinguishable() {
        let reasons: [AdapterLinkDisconnectReason] = [.bluetoothPoweredOff, .bluetoothUnauthorized, .bluetoothUnsupported]
        let states = reasons.map { reason -> AdapterLinkState? in
            let harness = Harness(powerState: power(for: reason))
            defer { harness.tearDown() }
            harness.start()
            return harness.link.state
        }

        XCTAssertEqual(states, reasons.map { .disconnected($0) })
    }

    /// 条件7: 利用不可の後に poweredOn へ変わると retrieve → connect の手順が始まります。
    ///
    /// 責務: 電源オフ・未許可・非対応のそれぞれから電源投入後の呼び出し順と `connecting` を確認します。
    func testPowerOnAfterUnavailableStartsRetrieveThenConnect() {
        for unavailable in [BLECentralPowerState.poweredOff, .unauthorized, .unsupported] {
            let harness = Harness(powerState: unavailable)
            defer { harness.tearDown() }
            harness.central.retrieveResult = [harness.peripheral]
            harness.start()

            harness.central.setPowerState(.poweredOn)

            XCTAssertEqual(harness.central.calls, [
                .retrievePeripherals([Harness.targetIdentifier]),
                .connect(Harness.targetIdentifier)
            ], "from \(unavailable)")
            XCTAssertEqual(harness.link.state, .connecting, "from \(unavailable)")
        }
    }

    /// 条件7: `ready` 中に poweredOff になると `disconnected(.bluetoothPoweredOff)` になり、再接続しません。
    ///
    /// 責務: 電源断の理由と、電源オフ中にconnect・retrieve・scanが追加で呼ばれないことを確認します。
    func testPowerOffWhileReadyReportsPoweredOffWithoutReconnecting() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()
        let callsBeforePowerOff = harness.central.calls

        harness.central.setPowerState(.poweredOff)

        XCTAssertEqual(harness.link.state, .disconnected(.bluetoothPoweredOff))
        XCTAssertEqual(harness.states.last, .disconnected(.bluetoothPoweredOff))
        let added = harness.central.calls.dropFirst(callsBeforePowerOff.count).filter {
            switch $0 {
            case .retrievePeripherals, .scanForPeripherals, .connect: true
            case .stopScan, .cancelConnection: false
            }
        }
        XCTAssertEqual(added, [])
    }

    /// 条件8: UUIDでない識別子では何も呼ばず `disconnected(.invalidIdentifier)` になります。
    ///
    /// 責務: 空文字・非UUID文字列・桁不足のそれぞれで呼び出しなしと理由を確認します。
    func testInvalidIdentifierCallsNothingAndReportsInvalidIdentifier() {
        for identifier in ["", "not-a-uuid", "6F1D2C3B-4A59-4E68-8D7C-0123456789A"] {
            let harness = Harness()
            defer { harness.tearDown() }
            harness.central.retrieveResult = [harness.peripheral]

            harness.start(systemIdentifier: identifier)

            XCTAssertEqual(harness.central.calls, [], "identifier=\(identifier)")
            XCTAssertEqual(harness.peripheral.calls, [], "identifier=\(identifier)")
            XCTAssertEqual(harness.link.state, .disconnected(.invalidIdentifier), "identifier=\(identifier)")
            XCTAssertEqual(harness.states, [.disconnected(.invalidIdentifier)], "identifier=\(identifier)")
        }
    }

    /// 利用不可の電源状態で開始した時の振る舞いを確認します。
    ///
    /// 責務: 取得可能な機器があっても中央役を一切呼ばず、指定理由の `disconnected` になることを確認します。
    /// - Parameters:
    ///   - power: 開始時の電源状態。
    ///   - reason: 期待する切断理由。
    private func assertUnavailablePower(
        _ power: BLECentralPowerState,
        reports reason: AdapterLinkDisconnectReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let harness = Harness(powerState: power)
        defer { harness.tearDown() }
        harness.central.retrieveResult = [harness.peripheral]

        harness.start()

        XCTAssertEqual(harness.central.calls, [], file: file, line: line)
        XCTAssertEqual(harness.link.state, .disconnected(reason), file: file, line: line)
        XCTAssertEqual(harness.states, [.disconnected(reason)], file: file, line: line)
    }

    /// 切断理由に対応する電源状態を返します。
    ///
    /// 責務: 利用不可理由をテスト開始時の電源状態へ対応付けます。
    /// - Parameter reason: 利用不可理由。
    /// - Returns: 対応する電源状態。
    private func power(for reason: AdapterLinkDisconnectReason) -> BLECentralPowerState {
        switch reason {
        case .bluetoothUnauthorized: .unauthorized
        case .bluetoothUnsupported: .unsupported
        default: .poweredOff
        }
    }
}
