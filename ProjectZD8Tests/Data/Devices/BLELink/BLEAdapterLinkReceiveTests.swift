import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink` のNotify受信の受け渡しを検証します(受け入れ条件10)。
@MainActor
final class BLEAdapterLinkReceiveTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// Notifyで届いたバイト列が届いた順に・欠落なく・内容を変えずにハンドラへ渡ります。
    ///
    /// 責務: 複数チャンク、全バイト値、同一内容の連続を流し、受信列が送った列と完全一致することを確認します。
    func testNotifiedValuesAreDeliveredInOrderWithoutLossOrChange() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()
        let values: [Data] = [
            Data("41 0C 1A F8\r".utf8),
            Data((0...255).map { UInt8($0) }),
            Data([0x00]),
            Data([0x3E]),
            Data([0x3E]),
            Data("OK\r\r>".utf8),
            Data([0xFF, 0x00, 0xFF])
        ]

        values.forEach { emitNotification($0, on: harness) }

        XCTAssertEqual(harness.received, values)
        XCTAssertEqual(harness.received.reduce(Data(), +), values.reduce(Data(), +))
    }

    /// 1件だけ届いた時もそのまま1件として渡ります。
    ///
    /// 責務: 最小の1バイト受信が加工されずに1回だけ渡ることを確認します。
    func testSingleByteNotificationIsDeliveredOnce() {
        let harness = Harness()
        defer { harness.tearDown() }
        harness.driveToReady()

        emitNotification(Data([0x0D]), on: harness)

        XCTAssertEqual(harness.received, [Data([0x0D])])
    }

    /// notify特性の値更新を流します。
    ///
    /// 責務: FFF1から1件の受信値を通知します。
    /// - Parameters:
    ///   - value: 受信値。
    ///   - harness: 通知先の準備。
    private func emitNotification(_ value: Data, on harness: Harness) {
        harness.peripheral.emit(.didReceiveValue(characteristicUUID: Fixtures.fff1Notify, value: value, errorDescription: nil))
    }
}
