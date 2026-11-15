import XCTest
@testable import ProjectZD8

/// `AutomaticRecordingPreferenceModel` の初回サインイン直後の選択画面の表示条件と選択結果を検証します。
@MainActor
final class AutomaticRecordingPreferenceModelPromptTests: XCTestCase {
    /// 自動記録設定の fake です。
    private var preference: AutomaticRecordingPreferenceFake!
    /// 表示済みフラグの fake です。
    private var completion: AutomaticRecordingChoicePromptCompletionFake!

    /// fake を指定の保存値で用意してモデルを生成します。
    ///
    /// 責務: 自動記録設定と表示済みフラグの初期値から、テスト対象のモデルを組み立てます。
    /// - Parameters:
    ///   - isEnabled: 自動記録設定の初期値。
    ///   - isCompleted: 表示済みフラグの初期値。
    /// - Returns: fake の保存境界につながったモデル。
    private func makeModel(isEnabled: Bool = false, isCompleted: Bool = false) -> AutomaticRecordingPreferenceModel {
        preference = AutomaticRecordingPreferenceFake(isEnabled: isEnabled)
        completion = AutomaticRecordingChoicePromptCompletionFake(isCompleted: isCompleted)
        return AutomaticRecordingPreferenceModel(
            preference: AutomaticRecordingPreferenceUseCase(preferencePort: preference),
            promptCompletion: AutomaticRecordingChoicePromptCompletionUseCase(completionPort: completion)
        )
    }

    /// 未表示の端末でサインインすると選択画面を表示します。
    ///
    /// 責務: サインイン前は偽、サインイン後は真になることを確認します。
    func testPromptPresentedAfterSignInOnUncompletedDevice() {
        let model = makeModel(isCompleted: false)
        XCTAssertFalse(model.state.isChoicePromptPresented)
        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertTrue(model.state.isChoicePromptPresented)
    }

    /// 表示済みの端末ではサインインし直しても選択画面を表示しません。
    ///
    /// 責務: 表示済みフラグが真の時、サインイン→サインアウト→サインインのどの時点でも偽であることを確認します。
    func testPromptNotPresentedOnCompletedDeviceEvenAfterSignInAgain() {
        let model = makeModel(isCompleted: true)
        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertFalse(model.state.isChoicePromptPresented)
        model.send(.signInStateChanged(isSignedIn: false))
        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertFalse(model.state.isChoicePromptPresented)
    }

    /// 選択画面で「自動で開始」を選ぶとオンが保存され、表示済みになり、選択画面を閉じます。
    ///
    /// 責務: 自動記録設定・表示済みフラグ・表示条件の3つへの反映を確認します。
    func testPromptChoiceStartAutomaticallySavesOnAndCompletes() {
        let model = makeModel(isEnabled: false, isCompleted: false)
        model.send(.signInStateChanged(isSignedIn: true))
        model.send(.promptChoiceSelected(.startAutomatically))
        XCTAssertEqual(preference.savedValues.last, true)
        XCTAssertTrue(preference.isEnabled)
        XCTAssertTrue(completion.isCompletedValue)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startAutomatically)
        XCTAssertFalse(model.state.isChoicePromptPresented)
    }

    /// 選択画面で「通知から開始」を選ぶとオフが保存され、表示済みになり、選択画面を閉じます。
    ///
    /// 責務: 保存済みがオンの端末でもオフへ置き換わり、表示済みになることを確認します。
    func testPromptChoiceStartFromNotificationSavesOffAndCompletes() {
        let model = makeModel(isEnabled: true, isCompleted: false)
        model.send(.signInStateChanged(isSignedIn: true))
        model.send(.promptChoiceSelected(.startFromNotification))
        XCTAssertEqual(preference.savedValues.last, false)
        XCTAssertFalse(preference.isEnabled)
        XCTAssertTrue(completion.isCompletedValue)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startFromNotification)
        XCTAssertFalse(model.state.isChoicePromptPresented)
    }

    /// 選択後にサインインし直しても選択画面は再表示しません。
    ///
    /// 責務: 選択で表示済みになった後、サインアウト→サインインで表示条件が偽のままであることを確認します。
    func testPromptNotPresentedAgainAfterChoiceAndReSignIn() {
        let model = makeModel(isCompleted: false)
        model.send(.signInStateChanged(isSignedIn: true))
        model.send(.promptChoiceSelected(.startFromNotification))
        model.send(.signInStateChanged(isSignedIn: false))
        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertFalse(model.state.isChoicePromptPresented)
    }

    /// 選ぶ前にサインアウトすると選択画面を閉じ、表示済みにはせず、次のサインインでまた表示します。
    ///
    /// 責務: サインアウトで表示条件が偽になり、表示済みフラグも自動記録設定も書き込まれないことを確認します。
    func testSignOutBeforeChoosingHidesPromptWithoutCompleting() {
        let model = makeModel(isCompleted: false)
        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertTrue(model.state.isChoicePromptPresented)

        model.send(.signInStateChanged(isSignedIn: false))
        XCTAssertFalse(model.state.isChoicePromptPresented)
        XCTAssertEqual(completion.markCount, 0)
        XCTAssertFalse(completion.isCompletedValue)
        XCTAssertTrue(preference.savedValues.isEmpty)

        model.send(.signInStateChanged(isSignedIn: true))
        XCTAssertTrue(model.state.isChoicePromptPresented)
    }
}
