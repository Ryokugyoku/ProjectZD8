import Foundation
import XCTest

/// Garage の紐付け失敗の文言キー `garage.error.session_assignment` が文字列カタログに日本語付きで存在することを検証します。
final class GarageSessionAssignmentLocalizationTests: XCTestCase {
    /// 検証するキーです(`VehicleManagementModel` が紐付け失敗時に設定する値)。
    private static let key = "garage.error.session_assignment"

    /// キーがカタログにあり、日本語の値が空ではありません。
    ///
    /// 責務: リポジトリの `Localizable.xcstrings` を JSON として読み、`ja` の `stringUnit` の値を確認します。
    func testKeyHasNonEmptyJapaneseValue() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("ProjectZD8/Resources/Localization/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try XCTUnwrap((object as? [String: Any])?["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[Self.key] as? [String: Any], "キーが無い: \(Self.key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let japanese = try XCTUnwrap(localizations["ja"] as? [String: Any], "日本語が無い")
        let unit = try XCTUnwrap(japanese["stringUnit"] as? [String: Any])
        let value = try XCTUnwrap(unit["value"] as? String)
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
