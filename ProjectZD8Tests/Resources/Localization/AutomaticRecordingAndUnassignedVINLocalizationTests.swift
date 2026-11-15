import Foundation
import XCTest
@testable import ProjectZD8

/// 自動記録設定・初回の選択画面・未登録車両の警告が使う文言キーが文字列カタログに日本語付きで存在することを検証します。
@MainActor
final class AutomaticRecordingAndUnassignedVINLocalizationTests: XCTestCase {
    /// 純粋型が返す文言キーをすべて集めます。
    ///
    /// 責務: 選択肢・選択画面・設定区画・警告(1台1件・1台複数件・複数台・失敗)・主要操作のキーを列挙します。
    /// - Returns: 重複を除いた文言キー。
    private static func collectedKeys() -> Set<String> {
        var keys = AutomaticRecordingChoice.allCases.flatMap { [$0.titleKey, $0.descriptionKey] }
        keys += [AutomaticRecordingChoicePromptContent.titleKey, AutomaticRecordingChoicePromptContent.messageKey]
        keys += [
            AutomaticRecordingSettingsSection.eyebrowKey,
            AutomaticRecordingSettingsSection.titleKey,
            AutomaticRecordingSettingsSection.descriptionKey,
            AutomaticRecordingSettingsSection.terminationNoticeKey
        ]
        for warning in unregisteredWarnings() + [.loadFailed] {
            keys += [warning.titleKey, warning.messageKey, warning.primaryAction?.titleKey].compactMap { $0 }
        }
        return Set(keys)
    }

    /// 本文の単数/複数の分岐を一通り通る未登録警告を作ります。
    ///
    /// 責務: 1台1件・1台2件・2台2件・3台5件の警告を返します。
    /// - Returns: 未登録車両の警告。
    private static func unregisteredWarnings() -> [UnassignedObservedVINWarning] {
        let shapes: [[String]] = [["A"], ["A", "A"], ["A", "B"], ["A", "B", "C", "A", "B"]]
        return shapes.map { vins in
            UnassignedObservedVINWarning(sessions: vins.enumerated().map { index, suffix in
                UnassignedObservedVINSessionFixture.session(vin: "JF1ZD8A11P900000\(suffix)", startedAt: Double(index))
            })
        }
    }

    /// すべてのキーがカタログにあり、日本語の値が空ではありません。
    ///
    /// 責務: 集めたキーごとに日本語の値を引き、欠落や空文字を検出します。
    func testAllKeysHaveNonEmptyJapaneseValue() throws {
        let japanese = try Self.japaneseValues()
        let keys = Self.collectedKeys()
        XCTAssertGreaterThanOrEqual(keys.count, 15)
        for key in keys.sorted() {
            let values = try XCTUnwrap(japanese[key], "キーが無いか日本語が無い: \(key)")
            XCTAssertFalse(values.isEmpty, key)
            for value in values {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
            }
        }
    }

    /// 未登録警告の本文は、日本語でも車両数とログ件数の2つの整数を埋め込みます。
    ///
    /// 責務: 本文キーの日本語の値に整数の書式指定子が2つあることを確認します。
    func testUnregisteredMessageEmbedsBothCounts() throws {
        let japanese = try Self.japaneseValues()
        let pattern = try NSRegularExpression(pattern: "%(\\d+\\$)?l?ld")
        for warning in Self.unregisteredWarnings() {
            let key = try XCTUnwrap(warning.messageKey)
            XCTAssertEqual(warning.messageArguments.count, 2, key)
            for value in try XCTUnwrap(japanese[key], key) {
                let count = pattern.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
                XCTAssertEqual(count, 2, "\(key): \(value)")
            }
        }
    }

    /// 文字列カタログを JSON として読み、キーごとの日本語の値を返します。
    ///
    /// 責務: リポジトリの `Localizable.xcstrings` から `ja` の `stringUnit` と、複数形などの分岐の値を集めます。
    /// - Returns: キーから日本語の値(分岐があれば全分岐)への対応。
    private static func japaneseValues() throws -> [String: [String]] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
        return strings.compactMapValues { entry in
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            guard let japanese = localizations?["ja"] else { return nil }
            let values = stringUnitValues(in: japanese)
            return values.isEmpty ? nil : values
        }
    }

    /// ローカライズ1件の中の `stringUnit.value` を再帰的に集めます。
    ///
    /// 責務: 単一値と `variations`(複数形・端末別)のどちらの形でも値を取り出します。
    /// - Parameter node: `ja` 以下の JSON ノード。
    /// - Returns: 見つかった値。
    private static func stringUnitValues(in node: Any) -> [String] {
        guard let dictionary = node as? [String: Any] else { return [] }
        if let value = (dictionary["stringUnit"] as? [String: Any])?["value"] as? String { return [value] }
        return dictionary.filter { $0.key != "stringUnit" }.values.flatMap { stringUnitValues(in: $0) }
    }
}
