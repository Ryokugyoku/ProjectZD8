import XCTest
@testable import ProjectZD8

/// `BLEResolvedUARTChannel.make(profile:writeCapability:)` の書き込み種別選択を検証します。
final class BLEResolvedUARTChannelTests: XCTestCase {
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// FFF0構成です。
    private var fff0: AppleBluetoothUARTProfile {
        AppleBluetoothUARTProfile.supported.first { $0.kind == .fff0 }!
    }

    /// 応答なしが使えれば応答なしを選び、構成のUUIDを写します。
    ///
    /// 責務: 応答なしのみの能力で全フィールドを確認します。
    func testWithoutResponseCapabilitySelectsWithoutResponse() {
        let channel = BLEResolvedUARTChannel.make(profile: fff0, writeCapability: Fixtures.writeWithoutResponseFFF2)
        XCTAssertEqual(channel, BLEResolvedUARTChannel(
            serviceUUID: "FFF0",
            notifyCharacteristicUUID: "FFF1",
            writeCharacteristicUUID: "FFF2",
            writeKind: .withoutResponse
        ))
    }

    /// 両方使える時も応答なしを選びます。
    ///
    /// 責務: 応答なしが優先されることを確認します。
    func testBothCapabilitiesSelectWithoutResponse() {
        XCTAssertEqual(BLEResolvedUARTChannel.make(profile: fff0, writeCapability: Fixtures.writeBothFFF2)?.writeKind, .withoutResponse)
    }

    /// 応答ありだけなら応答ありを選びます。
    ///
    /// 責務: 応答なし非対応の時の選択を確認します。
    func testWithResponseOnlySelectsWithResponse() {
        XCTAssertEqual(BLEResolvedUARTChannel.make(profile: fff0, writeCapability: Fixtures.writeWithResponseFFF2)?.writeKind, .withResponse)
    }

    /// 書き込み能力がなければ `nil` です。
    ///
    /// 責務: どちらの書き込みもできない時に送受信路を作らないことを確認します。
    func testNoWriteCapabilityReturnsNil() {
        XCTAssertNil(BLEResolvedUARTChannel.make(profile: fff0, writeCapability: Fixtures.nonWritableFFF2))
    }
}
