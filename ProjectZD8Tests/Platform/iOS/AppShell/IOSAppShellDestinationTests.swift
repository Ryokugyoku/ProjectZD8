#if os(iOS)
import SwiftUI
import XCTest
@testable import ProjectZD8

/// iOS AppShellの遷移先が、ホームへ統合したリアルタイム表示を含まない5件であることを検証します。
@MainActor
final class IOSAppShellDestinationTests: XCTestCase {
    /// 遷移先は home・history・maintenance・garage・settings の5件をこの順で持ちます。
    ///
    /// 責務: `allCases` の件数と順序を確かめます。
    func testAllCasesAreFiveDestinationsInOrder() {
        XCTAssertEqual(IOSAppShellDestination.allCases, [.home, .history, .maintenance, .garage, .settings])
    }

    /// 削除したリアルタイム表示の遷移先は rawValue から生成できません。
    ///
    /// 責務: `liveLog` が遷移先として存在しないことを確かめます。
    func testLiveLogIsNotADestination() {
        XCTAssertNil(IOSAppShellDestination(rawValue: "liveLog"))
    }

    /// 各遷移先の rawValue と id は UI テスト識別子 `ios-tab-<rawValue>` の元となる固定値です。
    ///
    /// 責務: 全遷移先の `rawValue` と `id` を確かめます。
    func testRawValuesAndIDsAreStable() {
        let expected: [IOSAppShellDestination: String] = [
            .home: "home",
            .history: "history",
            .maintenance: "maintenance",
            .garage: "garage",
            .settings: "settings"
        ]

        XCTAssertEqual(expected.count, IOSAppShellDestination.allCases.count)
        for (destination, rawValue) in expected {
            XCTAssertEqual(destination.rawValue, rawValue)
            XCTAssertEqual(destination.id, rawValue)
            XCTAssertEqual(IOSAppShellDestination(rawValue: rawValue), destination)
        }
    }

    /// 下部ナビゲーションの短い名称は遷移先ごとのローカライズキーです。
    ///
    /// 責務: 全遷移先の `compactTitle` を確かめます。
    func testCompactTitleKeys() {
        let expected: [IOSAppShellDestination: LocalizedStringKey] = [
            .home: "ios.navigation.home",
            .history: "ios.navigation.history",
            .maintenance: "ios.navigation.maintenance",
            .garage: "sidebar.garage",
            .settings: "ios.navigation.settings"
        ]

        XCTAssertEqual(expected.count, IOSAppShellDestination.allCases.count)
        for (destination, key) in expected {
            XCTAssertEqual(destination.compactTitle, key, "\(destination)")
        }
    }

    /// 遷移先のSF Symbol名は遷移先ごとの固定値で、互いに重複しません。
    ///
    /// 責務: 全遷移先の `systemImage` と重複のなさを確かめます。
    func testSystemImages() {
        let expected: [IOSAppShellDestination: String] = [
            .home: "house.fill",
            .history: "clock.arrow.circlepath",
            .maintenance: "wrench.and.screwdriver.fill",
            .garage: "car.side.fill",
            .settings: "slider.horizontal.3"
        ]

        XCTAssertEqual(expected.count, IOSAppShellDestination.allCases.count)
        for (destination, symbol) in expected {
            XCTAssertEqual(destination.systemImage, symbol, "\(destination)")
        }
        XCTAssertEqual(Set(IOSAppShellDestination.allCases.map(\.systemImage)).count, IOSAppShellDestination.allCases.count)
    }
}
#endif
