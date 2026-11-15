import Foundation
import XCTest
@testable import ProjectZD8

/// `VehicleDetectionNotificationCatalog` の識別子・カテゴリ・割り込みレベル・操作判定と文言キーの実在を検証します。
final class VehicleDetectionNotificationCatalogTests: XCTestCase {
    /// 検証対象の定義です。
    private let catalog = VehicleDetectionNotificationCatalog()
    /// VIN の例です。
    private static let vin = "1D4GP00R55B123456"

    /// 検知通知は何度組み立てても同じ識別子(置き換え式)で、[記録開始]カテゴリ付き・Time Sensitive です。
    ///
    /// 責務: VIN の有無と繰り返しで識別子が変わらず、カテゴリが[記録開始]操作のものであることを確認します。
    func testVehicleDetectedUsesFixedIdentifierCategoryAndTimeSensitive() throws {
        let contents = [catalog.vehicleDetected(vin: nil), catalog.vehicleDetected(vin: Self.vin), catalog.vehicleDetected(vin: nil)]
        XCTAssertEqual(Set(contents.map(\.identifier)).count, 1)
        XCTAssertFalse(contents[0].identifier.isEmpty)
        let categories = Set(contents.map(\.categoryIdentifier))
        XCTAssertEqual(categories.count, 1, "カテゴリ識別子は何度組み立てても同じ")
        let category = try XCTUnwrap(contents[0].categoryIdentifier, "検知通知にはカテゴリが付く")
        XCTAssertFalse(category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotEqual(category, contents[0].identifier)
        XCTAssertNotEqual(category, catalog.recordingStarted(vin: nil).identifier)
        XCTAssertTrue(catalog.isRecordingStartSelection(
            actionIdentifier: VehicleDetectionNotificationCatalog.startRecordingActionIdentifier, categoryIdentifier: category
        ), "検知通知のカテゴリで[記録開始]が記録開始として扱われる")
        for content in contents {
            XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        }
    }

    /// 「記録を開始しました」通知は検知通知とは別の固定識別子です。
    ///
    /// 責務: VIN の有無で識別子が変わらず、検知通知の識別子と異なることを確認します。
    func testRecordingStartedUsesSeparateFixedIdentifier() {
        let withoutVIN = catalog.recordingStarted(vin: nil)
        let withVIN = catalog.recordingStarted(vin: Self.vin)
        XCTAssertEqual(withoutVIN.identifier, withVIN.identifier)
        XCTAssertEqual(catalog.recordingStarted(vin: nil).identifier, withoutVIN.identifier, "何度取得しても同じ")
        XCTAssertFalse(withoutVIN.identifier.isEmpty)
        XCTAssertNotEqual(withoutVIN.identifier, catalog.vehicleDetected(vin: nil).identifier)
    }

    /// [記録開始]操作の選択だけを記録開始として扱います。
    ///
    /// 責務: 監視カテゴリの[記録開始]操作は `true`、本文タップ・閉じる操作・別カテゴリは `false` であることを確認します。
    func testOnlyStartRecordingActionInDetectionCategoryStartsRecording() {
        let category = VehicleDetectionNotificationCatalog.categoryIdentifier
        let action = VehicleDetectionNotificationCatalog.startRecordingActionIdentifier
        XCTAssertTrue(catalog.isRecordingStartSelection(actionIdentifier: action, categoryIdentifier: category))
        XCTAssertFalse(catalog.isRecordingStartSelection(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
            categoryIdentifier: category
        ))
        XCTAssertFalse(catalog.isRecordingStartSelection(
            actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier",
            categoryIdentifier: category
        ))
        XCTAssertFalse(catalog.isRecordingStartSelection(actionIdentifier: action, categoryIdentifier: "OTHER_CATEGORY"))
        XCTAssertFalse(catalog.isRecordingStartSelection(actionIdentifier: action, categoryIdentifier: ""))
    }

    /// 通知と[記録開始]操作が使う文言キーは文字列カタログに存在し、日本語の値が空ではありません。
    ///
    /// 責務: 全通知内容のタイトル・本文キーと操作名キーを `Localizable.xcstrings` から引き、引数を持つ本文には `%@` があることを確認します。
    func testLocalizationKeysExistWithNonEmptyJapaneseValues() throws {
        let japanese = try Self.japaneseValues()
        let contents = [nil, Self.vin].flatMap { [catalog.vehicleDetected(vin: $0), catalog.recordingStarted(vin: $0)] }
        var keys = [VehicleDetectionNotificationCatalog.startRecordingActionTitleKey]
        keys += contents.flatMap { [$0.titleKey, $0.bodyKey] }
        for key in keys {
            let value = try XCTUnwrap(japanese[key], "キーが無いか日本語が無い: \(key)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
        }
        for content in contents where !content.bodyArguments.isEmpty {
            XCTAssertTrue(japanese[content.bodyKey]?.contains("%@") == true, "引数の埋め込み先が無い: \(content.bodyKey)")
        }
    }

    /// 文字列カタログを JSON として読み、キーごとの日本語の値を返します。
    ///
    /// 責務: このテストファイルの位置からリポジトリの `Localizable.xcstrings` を特定し、`ja` の `stringUnit.value` を集めます。
    /// - Returns: キーから日本語の値への対応。
    private static func japaneseValues() throws -> [String: String] {
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
            let unit = (localizations?["ja"] as? [String: Any])?["stringUnit"] as? [String: Any]
            return unit?["value"] as? String
        }
    }
}
