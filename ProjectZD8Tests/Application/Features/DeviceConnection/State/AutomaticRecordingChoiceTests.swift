import XCTest
@testable import ProjectZD8

/// 記録開始方法の選択肢 `AutomaticRecordingChoice` の写像と文言キーを検証します。
@MainActor
final class AutomaticRecordingChoiceTests: XCTestCase {
    /// 選択肢は「通知から開始」と「自動で開始」の2つです。
    ///
    /// 責務: `allCases` が2件で、両方の選択肢を含むことを確認します。
    func testHasExactlyTwoChoices() {
        XCTAssertEqual(AutomaticRecordingChoice.allCases.count, 2)
        XCTAssertEqual(Set(AutomaticRecordingChoice.allCases), [.startFromNotification, .startAutomatically])
    }

    /// 自動記録オフの保存値は「通知から開始」になります。
    ///
    /// 責務: `init(isAutomaticRecordingEnabled: false)` の分岐を確認します。
    func testDisabledPreferenceMapsToStartFromNotification() {
        XCTAssertEqual(AutomaticRecordingChoice(isAutomaticRecordingEnabled: false), .startFromNotification)
    }

    /// 自動記録オンの保存値は「自動で開始」になります。
    ///
    /// 責務: `init(isAutomaticRecordingEnabled: true)` の分岐を確認します。
    func testEnabledPreferenceMapsToStartAutomatically() {
        XCTAssertEqual(AutomaticRecordingChoice(isAutomaticRecordingEnabled: true), .startAutomatically)
    }

    /// 「通知から開始」はオフ、「自動で開始」はオンとして保存されます。
    ///
    /// 責務: `isAutomaticRecordingEnabled` の両分岐を確認します。
    func testSavedPreferenceValueOfEachChoice() {
        XCTAssertFalse(AutomaticRecordingChoice.startFromNotification.isAutomaticRecordingEnabled)
        XCTAssertTrue(AutomaticRecordingChoice.startAutomatically.isAutomaticRecordingEnabled)
    }

    /// 選択肢と保存値の写像は往復しても変わりません。
    ///
    /// 責務: 各選択肢の保存値から生成し直すと元の選択肢へ戻ることを確認します。
    func testChoiceRoundTripsThroughPreferenceValue() {
        for choice in AutomaticRecordingChoice.allCases {
            XCTAssertEqual(AutomaticRecordingChoice(isAutomaticRecordingEnabled: choice.isAutomaticRecordingEnabled), choice)
        }
    }

    /// 識別子は選択肢ごとに異なります。
    ///
    /// 責務: `id` が2つの選択肢で重複しないことを確認します。
    func testIdentifiersAreDistinct() {
        XCTAssertNotEqual(AutomaticRecordingChoice.startFromNotification.id, AutomaticRecordingChoice.startAutomatically.id)
    }

    /// 表題キーと説明キーは空でなく、選択肢ごとに異なり、表題と説明でも異なります。
    ///
    /// 責務: `titleKey` と `descriptionKey` の両分岐が4つの別々のキーを返すことを確認します。
    func testTitleAndDescriptionKeysAreDistinctPerChoice() {
        let keys = AutomaticRecordingChoice.allCases.flatMap { [$0.titleKey, $0.descriptionKey] }
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertFalse(keys.contains { $0.isEmpty })
    }

    /// 選択肢のアイコン名は空ではありません。
    ///
    /// 責務: `systemImageName` の両分岐が描画できる名前を返すことを確認します。
    func testSystemImageNamesAreNotEmpty() {
        for choice in AutomaticRecordingChoice.allCases {
            XCTAssertFalse(choice.systemImageName.isEmpty, choice.id)
        }
    }
}
