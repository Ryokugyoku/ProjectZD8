import XCTest
@testable import ProjectZD8

/// 自動記録設定の表示状態 `AutomaticRecordingPreferenceState` の計算プロパティを検証します。
@MainActor
final class AutomaticRecordingPreferenceStateTests: XCTestCase {
    /// 既定の状態では選択画面を表示せず、「通知から開始」が選択中です。
    ///
    /// 責務: 既定値(未サインイン・未表示・オフ)での2つの計算プロパティを確認します。
    func testDefaultStateIsSignedOutAndStartFromNotification() {
        let state = AutomaticRecordingPreferenceState()
        XCTAssertFalse(state.isChoicePromptPresented)
        XCTAssertEqual(state.settingsSection.selectedChoice, .startFromNotification)
    }

    /// 設定区画の選択中は保存値に従います。
    ///
    /// 責務: `settingsSection` がオン・オフの両方で保存値どおりの選択肢を返すことを確認します。
    func testSettingsSectionFollowsSavedPreference() {
        var state = AutomaticRecordingPreferenceState()
        state.isAutomaticRecordingEnabled = true
        XCTAssertEqual(state.settingsSection.selectedChoice, .startAutomatically)
        state.isAutomaticRecordingEnabled = false
        XCTAssertEqual(state.settingsSection.selectedChoice, .startFromNotification)
    }

    /// 選択画面はサインイン済みかつ未表示の時だけ表示します。
    ///
    /// 責務: `isChoicePromptPresented` をサインイン状態と表示済みフラグの4通りで確認します。
    func testChoicePromptPresentedOnlyWhenSignedInAndNotCompleted() {
        let cases: [(isSignedIn: Bool, isCompleted: Bool, expected: Bool)] = [
            (true, false, true),
            (true, true, false),
            (false, false, false),
            (false, true, false)
        ]
        for item in cases {
            var state = AutomaticRecordingPreferenceState()
            state.isSignedIn = item.isSignedIn
            state.isChoicePromptCompleted = item.isCompleted
            XCTAssertEqual(state.isChoicePromptPresented, item.expected, "signedIn=\(item.isSignedIn) completed=\(item.isCompleted)")
        }
    }
}
