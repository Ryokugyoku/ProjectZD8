#if os(macOS)
import SwiftUI
import XCTest
@testable import ProjectZD8

/// macOSサイドバーの遷移先が、ホームへ統合したリアルタイム表示を含まない5件で、⌘1〜⌘5を重複なく持つことを検証します。
@MainActor
final class MacOSSidebarDestinationTests: XCTestCase {
    /// 遷移先は home・history・maintenance・garage・settings の5件をこの順で持ちます。
    ///
    /// 責務: `allCases` の件数と順序を確かめます。
    func testAllCasesAreFiveDestinationsInOrder() {
        XCTAssertEqual(MacOSSidebarDestination.allCases, [.home, .history, .maintenance, .garage, .settings])
    }

    /// 削除したリアルタイム表示の遷移先は rawValue から生成できません。
    ///
    /// 責務: `liveLog` が遷移先として存在しないことを確かめます。
    func testLiveLogIsNotADestination() {
        XCTAssertNil(MacOSSidebarDestination(rawValue: "liveLog"))
    }

    /// 各遷移先の rawValue と id は UI テスト識別子 `macos-sidebar-<rawValue>` の元となる固定値です。
    ///
    /// 責務: 全遷移先の `rawValue` と `id` を確かめます。
    func testRawValuesAndIDsAreStable() {
        let expected: [MacOSSidebarDestination: String] = [
            .home: "home",
            .history: "history",
            .maintenance: "maintenance",
            .garage: "garage",
            .settings: "settings"
        ]

        XCTAssertEqual(expected.count, MacOSSidebarDestination.allCases.count)
        for (destination, rawValue) in expected {
            XCTAssertEqual(destination.rawValue, rawValue)
            XCTAssertEqual(destination.id, rawValue)
            XCTAssertEqual(MacOSSidebarDestination(rawValue: rawValue), destination)
        }
    }

    /// ショートカットは home ⌘1、history ⌘2、maintenance ⌘3、garage ⌘4、settings ⌘5 です。
    ///
    /// 責務: 全遷移先の `shortcut` と `shortcutLabel` の対応を確かめます。
    func testShortcutsAreCommandOneThroughFive() {
        let expected: [MacOSSidebarDestination: Character] = [
            .home: "1",
            .history: "2",
            .maintenance: "3",
            .garage: "4",
            .settings: "5"
        ]

        XCTAssertEqual(expected.count, MacOSSidebarDestination.allCases.count)
        for (destination, number) in expected {
            XCTAssertEqual(destination.shortcut.character, number, "\(destination)")
            XCTAssertEqual(destination.shortcutLabel, "⌘\(number)", "\(destination)")
        }
    }

    /// ショートカットとその表記は遷移先どうしで重複しません。
    ///
    /// 責務: `shortcut` と `shortcutLabel` の一意性を確かめます。
    func testShortcutsAreUnique() {
        let destinations = MacOSSidebarDestination.allCases

        XCTAssertEqual(Set(destinations.map(\.shortcut.character)).count, destinations.count)
        XCTAssertEqual(Set(destinations.map(\.shortcutLabel)).count, destinations.count)
    }

    /// タイトルと補足文は遷移先ごとのローカライズキーです。
    ///
    /// 責務: 全遷移先の `title` と `subtitle` を確かめます。
    func testTitleAndSubtitleKeys() {
        let expected: [MacOSSidebarDestination: (title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
            .home: ("sidebar.home", "sidebar.home.subtitle"),
            .history: ("sidebar.connection_history", "sidebar.connection_history.subtitle"),
            .maintenance: ("sidebar.maintenance", "sidebar.maintenance.subtitle"),
            .garage: ("sidebar.garage", "sidebar.garage.subtitle"),
            .settings: ("sidebar.settings", "sidebar.settings.subtitle")
        ]

        XCTAssertEqual(expected.count, MacOSSidebarDestination.allCases.count)
        for (destination, keys) in expected {
            XCTAssertEqual(destination.title, keys.title, "\(destination)")
            XCTAssertEqual(destination.subtitle, keys.subtitle, "\(destination)")
        }
    }

    /// 遷移先のSF Symbol名は遷移先ごとの固定値です。
    ///
    /// 責務: 全遷移先の `systemImage` を確かめます。
    func testSystemImages() {
        let expected: [MacOSSidebarDestination: String] = [
            .home: "house.fill",
            .history: "clock.arrow.circlepath",
            .maintenance: "wrench.adjustable.fill",
            .garage: "car.2.fill",
            .settings: "slider.horizontal.3"
        ]

        XCTAssertEqual(expected.count, MacOSSidebarDestination.allCases.count)
        for (destination, symbol) in expected {
            XCTAssertEqual(destination.systemImage, symbol, "\(destination)")
        }
    }
}
#endif
