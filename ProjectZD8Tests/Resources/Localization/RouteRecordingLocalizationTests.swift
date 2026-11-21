import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルート記録の設定文言と位置情報の用途説明が ja / en / es で揃っていることを検証します。
@MainActor
final class RouteRecordingLocalizationTests: XCTestCase {
    /// 検証する言語です。
    private static let languages = ["ja", "en", "es"]

    /// 仕様で定めた設定画面の文言キーです。
    private static let settingsKeys = [
        "settings.route_recording.eyebrow", "settings.route_recording.title",
        "settings.route_recording.description", "settings.route_recording.toggle",
        "settings.route_recording.reduced_accuracy_notice", "settings.route_recording.open_system_settings",
        "settings.route_recording.status.off", "settings.route_recording.status.awaiting_permission",
        "settings.route_recording.status.records_in_background", "settings.route_recording.status.foreground_only",
        "settings.route_recording.status.denied", "settings.route_recording.status.restricted",
        "settings.route_recording.status.unsupported_platform"
    ]

    /// Info.plist の位置情報の用途説明キーです。
    private static let infoPlistKeys = [
        "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"
    ]

    /// 文字列カタログを JSON として読み、`strings` を返します。
    ///
    /// 責務: テストファイル位置からリポジトリ直下を求め、指定ファイルの `strings` を取り出します。
    private func loadStrings(fileName: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("ProjectZD8/Resources/Localization/\(fileName)")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any], fileName)
    }

    /// あるキー・言語の訳を返します。
    ///
    /// 責務: `localizations.<言語>.stringUnit.value` を取り出します。無ければ nil です。
    private func translation(_ key: String, language: String, in strings: [String: Any]) -> String? {
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    /// 全キーの全言語に空でない訳があることを確認します。
    ///
    /// 責務: 欠落・空白のみの訳を XCTFail で報告します。
    private func assertTranslated(_ keys: [String], in strings: [String: Any]) {
        for key in keys {
            for language in Self.languages {
                let value = translation(key, language: language, in: strings)
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                XCTAssertFalse(trimmed.isEmpty, "訳が無いか空: \(key) [\(language)]")
            }
        }
    }

    /// 設定画面の13キーに ja / en / es の訳があります。
    ///
    /// 責務: `Localizable.xcstrings` を確認します。
    func testSettingsKeysAreTranslatedInAllLanguages() throws {
        assertTranslated(Self.settingsKeys, in: try loadStrings(fileName: "Localizable.xcstrings"))
    }

    /// 位置情報の用途説明の2キーに ja / en / es の訳があります。
    ///
    /// 責務: `InfoPlist.xcstrings` を確認します。
    func testInfoPlistUsageDescriptionsAreTranslatedInAllLanguages() throws {
        assertTranslated(Self.infoPlistKeys, in: try loadStrings(fileName: "InfoPlist.xcstrings"))
    }

    /// 型が返す状態の文言キーがすべてカタログにあります。
    ///
    /// 責務: `RouteRecordingSettingsStatus.allCases` の `localizationKey` を確認します。
    func testStatusLocalizationKeysExistInCatalog() throws {
        let strings = try loadStrings(fileName: "Localizable.xcstrings")
        XCTAssertEqual(RouteRecordingSettingsStatus.allCases.count, 7)
        for status in RouteRecordingSettingsStatus.allCases {
            XCTAssertNotNil(strings[status.localizationKey], "カタログに無い: \(status.localizationKey)")
        }
    }

    /// 区画の6つの static キーがすべてカタログにあります。
    ///
    /// 責務: `RouteRecordingSettingsSection` の各キーが `Localizable.xcstrings` にあることを確認します。
    func testSectionKeysExistInCatalog() throws {
        let strings = try loadStrings(fileName: "Localizable.xcstrings")
        let keys = [
            RouteRecordingSettingsSection.eyebrowKey, RouteRecordingSettingsSection.titleKey,
            RouteRecordingSettingsSection.descriptionKey, RouteRecordingSettingsSection.toggleKey,
            RouteRecordingSettingsSection.reducedAccuracyNoticeKey, RouteRecordingSettingsSection.openSystemSettingsKey
        ]
        for key in keys {
            XCTAssertNotNil(strings[key], "カタログに無い: \(key)")
        }
    }
}
