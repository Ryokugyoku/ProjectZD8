import Foundation
import XCTest
@testable import ProjectZD8

/// 「記録を開始できませんでした」通知と、車両を特定できなかったログの警告・紐付け画面が使う文言キーが、
/// 文字列カタログに既存の全言語(ja・en・es)で空でない値を持つことを検証します。
///
/// 仕様: U4 受け入れ条件 7・16(文言は `Localizable.xcstrings` に既存の全言語で追加)。
@MainActor
final class VehicleUnknownSessionAndRecordingStartFailureLocalizationTests: XCTestCase {
    /// 検証する言語です。
    private static let languages = ["ja", "en", "es"]

    /// iOS の紐付け画面が直接使う文言キーです(画面は iOS 専用で macOS テストから型を参照できないため列挙します)。
    private static let assignmentScreenKeys = [
        "vehicle_unknown.assignment.title",
        "vehicle_unknown.assignment.sessions.header",
        "vehicle_unknown.assignment.vehicles.header",
        "vehicle_unknown.assignment.assign",
        "vehicle_unknown.assignment.close",
    ]

    /// 純粋型が返す文言キーと、紐付け画面の文言キーを集めます。
    ///
    /// 責務: 失敗通知(見出し・理由ごとの本文)・警告(1件・複数件・失敗)・主要操作・紐付け画面の案内と失敗のキーを列挙します。
    /// - Returns: 重複を除いた文言キー。
    private static func collectedKeys() -> Set<String> {
        let catalog = VehicleDetectionNotificationCatalog()
        var keys = AdapterLinkRecordingStartFailureReason.allCases.flatMap {
            let content = catalog.recordingStartFailed(reason: $0)
            return [content.titleKey, content.bodyKey]
        }
        let warnings: [VehicleUnknownSessionWarning] = [.sessions(count: 1), .sessions(count: 2), .loadFailed]
        for warning in warnings {
            keys += [warning.titleKey, warning.messageKey, warning.primaryAction?.titleKey].compactMap { $0 }
        }
        let assignment = VehicleUnknownSessionAssignmentState()
        keys += [assignment.noVehicleMessageKey(among: []), "vehicle_unknown.assignment.failure"].compactMap { $0 }
        keys += assignmentScreenKeys
        return Set(keys)
    }

    /// すべてのキーがカタログにあり、ja・en・es の値が空ではありません。
    ///
    /// 責務: 集めたキーと言語の組ごとに値を引き、欠落や空文字を検出します。
    func testAllKeysHaveNonEmptyValuesInEveryLanguage() throws {
        let values = try Self.localizedValues()
        let keys = Self.collectedKeys()
        XCTAssertGreaterThanOrEqual(keys.count, 16)
        for key in keys.sorted() {
            for language in Self.languages {
                let value = try XCTUnwrap(values[key]?[language], "キーか \(language) の値が無い: \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) / \(language)")
            }
        }
    }

    /// 件数つきの警告の本文は、全言語で整数の書式指定子を1つだけ持ちます。
    ///
    /// 責務: 1件・複数件の本文キーの ja・en・es の値に `%lld`(位置指定を含む)が1つあることを確認します(受け入れ条件 11)。
    func testCountMessageEmbedsCountInEveryLanguage() throws {
        let values = try Self.localizedValues()
        let pattern = try NSRegularExpression(pattern: "%(\\d+\\$)?l?ld")
        for warning in [VehicleUnknownSessionWarning.sessions(count: 1), .sessions(count: 2)] {
            let key = try XCTUnwrap(warning.messageKey)
            XCTAssertEqual(warning.messageArguments.count, 1, key)
            for language in Self.languages {
                let value = try XCTUnwrap(values[key]?[language], "\(key) / \(language)")
                let count = pattern.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
                XCTAssertEqual(count, 1, "\(key) / \(language): \(value)")
            }
        }
    }

    /// 文字列カタログを JSON として読み、キーごと・言語ごとの値を返します。
    ///
    /// 責務: リポジトリの `Localizable.xcstrings` から各言語の `stringUnit.value` を集めます。
    /// - Returns: キーから「言語から値への対応」への対応。
    private static func localizedValues() throws -> [String: [String: String]] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
        return strings.compactMapValues { entry in
            guard let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] else { return nil }
            return localizations.compactMapValues { localization in
                let unit = (localization as? [String: Any])?["stringUnit"] as? [String: Any]
                return unit?["value"] as? String
            }
        }
    }
}
