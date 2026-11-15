import XCTest
@testable import ProjectZD8

/// 設定画面の「車両検知時の記録開始」区画 `AutomaticRecordingSettingsSection` を検証します。
@MainActor
final class AutomaticRecordingSettingsSectionTests: XCTestCase {
    /// 自動記録オフなら「通知から開始」だけが選択中です。
    ///
    /// 責務: オフの保存値で `selectedChoice` と `isSelected(_:)` の両分岐を確認します。
    func testDisabledPreferenceSelectsStartFromNotification() {
        let section = AutomaticRecordingSettingsSection(isAutomaticRecordingEnabled: false)
        XCTAssertEqual(section.selectedChoice, .startFromNotification)
        XCTAssertTrue(section.isSelected(.startFromNotification))
        XCTAssertFalse(section.isSelected(.startAutomatically))
    }

    /// 自動記録オンなら「自動で開始」だけが選択中です。
    ///
    /// 責務: オンの保存値で `selectedChoice` と `isSelected(_:)` の両分岐を確認します。
    func testEnabledPreferenceSelectsStartAutomatically() {
        let section = AutomaticRecordingSettingsSection(isAutomaticRecordingEnabled: true)
        XCTAssertEqual(section.selectedChoice, .startAutomatically)
        XCTAssertTrue(section.isSelected(.startAutomatically))
        XCTAssertFalse(section.isSelected(.startFromNotification))
    }

    /// どちらの保存値でも選択中の選択肢は常に1つです。
    ///
    /// 責務: `choices` のうち `isSelected` が真になるものが1件だけであることを確認します。
    func testExactlyOneChoiceIsSelectedForEitherPreference() {
        for isEnabled in [false, true] {
            let section = AutomaticRecordingSettingsSection(isAutomaticRecordingEnabled: isEnabled)
            XCTAssertEqual(section.choices.filter(section.isSelected).count, 1, "isEnabled=\(isEnabled)")
        }
    }

    /// 区画は2つの選択肢を重複なく並べます。
    ///
    /// 責務: `choices` が2つの選択肢を1件ずつ含むことを確認します。
    func testChoicesContainBothOptionsOnce() {
        let choices = AutomaticRecordingSettingsSection(isAutomaticRecordingEnabled: false).choices
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(Set(choices), [.startFromNotification, .startAutomatically])
    }

    /// 区画の文言キーと、アプリスイッチャーで終了すると自動検知が止まる旨の案内キーは空でなく互いに異なります。
    ///
    /// 責務: 4つの静的キーがすべて得られ、案内キーが他の文言と取り違えられていないことを確認します。
    func testSectionKeysIncludingTerminationNoticeAreDistinct() {
        let keys = [
            AutomaticRecordingSettingsSection.eyebrowKey,
            AutomaticRecordingSettingsSection.titleKey,
            AutomaticRecordingSettingsSection.descriptionKey,
            AutomaticRecordingSettingsSection.terminationNoticeKey
        ]
        XCTAssertFalse(keys.contains { $0.isEmpty })
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
