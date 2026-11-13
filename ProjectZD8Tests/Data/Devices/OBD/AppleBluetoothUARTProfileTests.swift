#if os(iOS) || os(macOS)
import XCTest
@testable import ProjectZD8

/// AppleプラットフォームのBLE UARTに対する既知UUIDと能力照合を検証します。
final class AppleBluetoothUARTProfileTests: XCTestCase {
    /// 提供資料のMX+単一Characteristic構成を解決できることを検証します。
    ///
    /// 責務: b349 ServiceのNotify兼Write能力が実験プロファイルへ一致することを確認します。
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

    /// SwiftOBD2とOBDLink CX公式仕様のFFF0構成を解決できることを検証します。
    ///
    /// 責務: 分離したFFF1 NotifyとFFF2 Write能力がFFF0プロファイルへ一致することを確認します。
    func testResolvesFFF0SplitCharacteristicProfile() {
        let profile = AppleBluetoothUARTProfileResolver().resolve(
            services: [
                "FFF0": [
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFF1",
                        supportsNotify: true,
                        supportsWriteWithResponse: false,
                        supportsWriteWithoutResponse: false
                    ),
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFF2",
                        supportsNotify: false,
                        supportsWriteWithResponse: true,
                        supportsWriteWithoutResponse: true
                    )
                ]
            ]
        )

        XCTAssertEqual(profile?.kind, .fff0)
    }

    /// UUIDだけ一致しても必要なプロパティがなければ採用しないことを検証します。
    ///
    /// 責務: NotifyまたはWrite能力を欠く類似ServiceがUARTとして誤採用されないことを確認します。
    func testRejectsProfileWithoutRequiredProperties() {
        let profile = AppleBluetoothUARTProfileResolver().resolve(
            services: [
                "FFE0": [
                    AppleBluetoothCharacteristicCapability(
                        uuid: "FFE1",
                        supportsNotify: false,
                        supportsWriteWithResponse: false,
                        supportsWriteWithoutResponse: false
                    )
                ]
            ]
        )

        XCTAssertNil(profile)
    }
}
#endif
