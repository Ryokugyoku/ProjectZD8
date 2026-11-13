#if os(iOS) || os(macOS)
import XCTest
@testable import ProjectZD8

/// BLE UARTの既知UUIDと能力照合を検証します。
final class AppleBluetoothUARTProfileTests: XCTestCase {
    /// 責務: MX+の単一Characteristic構成を解決できることを確認します。
    func testResolvesExperimentalMXPlusSingleCharacteristicProfile() {
        let characteristic = AppleBluetoothCharacteristicCapability(
            uuid: "b3491406-44e4-4d83-97c5-ce3190130001",
            supportsNotify: true,
            supportsWriteWithResponse: false,
            supportsWriteWithoutResponse: true
        )
        let profile = AppleBluetoothUARTProfileResolver().resolve(
            services: ["b3491406-44e4-4d83-97c5-ce3190130000": [characteristic]]
        )
        XCTAssertEqual(profile?.kind, .obdLinkMXPlusExperimental)
    }

    /// 責務: 分離したFFF1 NotifyとFFF2 WriteがFFF0プロファイルへ一致することを確認します。
    func testResolvesFFF0SplitCharacteristicProfile() {
        let profile = AppleBluetoothUARTProfileResolver().resolve(
            services: [
                "FFF0": [
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFF1", supportsNotify: true,
                        supportsWriteWithResponse: false, supportsWriteWithoutResponse: false
                    ),
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFF2", supportsNotify: false,
                        supportsWriteWithResponse: true, supportsWriteWithoutResponse: true
                    )
                ]
            ]
        )
        XCTAssertEqual(profile?.kind, .fff0)
    }

    /// 責務: UUIDが一致しても必要な能力を欠く構成を採用しないことを確認します。
    func testRejectsProfileWithoutRequiredProperties() {
        let profile = AppleBluetoothUARTProfileResolver().resolve(
            services: [
                "FFE0": [
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFE1", supportsNotify: false,
                        supportsWriteWithResponse: false, supportsWriteWithoutResponse: false
                    )
                ]
            ]
        )
        XCTAssertNil(profile)
    }
}
#endif
