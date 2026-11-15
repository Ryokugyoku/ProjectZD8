import XCTest
@testable import ProjectZD8

/// 初回の選択画面の内容 `AutomaticRecordingChoicePromptContent` を検証します。
@MainActor
final class AutomaticRecordingChoicePromptContentTests: XCTestCase {
    /// 見出しと説明のキーは空でなく、互いに異なります。
    ///
    /// 責務: `titleKey` と `messageKey` が別々の文言を指すことを確認します。
    func testTitleAndMessageKeysAreDistinct() {
        XCTAssertFalse(AutomaticRecordingChoicePromptContent.titleKey.isEmpty)
        XCTAssertFalse(AutomaticRecordingChoicePromptContent.messageKey.isEmpty)
        XCTAssertNotEqual(AutomaticRecordingChoicePromptContent.titleKey, AutomaticRecordingChoicePromptContent.messageKey)
    }

    /// 選択画面は2つの選択肢をどちらも重複なく出します。
    ///
    /// 責務: `choices` が「通知から開始」と「自動で開始」を1件ずつ含むことを確認します。
    func testChoicesContainBothOptionsOnce() {
        let choices = AutomaticRecordingChoicePromptContent.choices
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(Set(choices), [.startFromNotification, .startAutomatically])
    }
}
