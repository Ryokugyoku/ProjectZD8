import XCTest
@testable import ProjectZD8

/// `AutomaticRecordingPreferenceModel` が設定画面と初回の選択画面の操作を保存と表示状態へ反映することを検証します。
@MainActor
final class AutomaticRecordingPreferenceModelTests: XCTestCase {
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

    /// 起動時は保存済みの自動記録設定を選択中として表示し、未サインインなので選択画面は出しません。
    ///
    /// 責務: オン・オフ両方の保存値が初期状態の選択中へ反映され、未表示でも表示条件が偽であることを確認します。
    func testInitialStateReflectsSavedPreferenceAndIsSignedOut() {
        XCTAssertEqual(makeModel(isEnabled: true).state.settingsSection.selectedChoice, .startAutomatically)
        let model = makeModel(isEnabled: false, isCompleted: false)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startFromNotification)
        XCTAssertFalse(model.state.isChoicePromptPresented)
    }

    /// 設定画面で「自動で開始」を選ぶとオンが保存され、選択中が切り替わります。
    ///
    /// 責務: 設定の選択がユースケース経由で保存され、表示へ反映されることを確認します。
    func testSettingsChoiceSavesEnabledPreference() {
        let model = makeModel(isEnabled: false)
        model.send(.settingsChoiceSelected(.startAutomatically))
        XCTAssertEqual(preference.savedValues.last, true)
        XCTAssertTrue(preference.isEnabled)
        XCTAssertTrue(model.state.isAutomaticRecordingEnabled)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startAutomatically)
    }

    /// 設定画面で「通知から開始」を選ぶとオフが保存され、選択中が切り替わります。
    ///
    /// 責務: オンからオフへの変更が保存と表示へ反映されることを確認します。
    func testSettingsChoiceSavesDisabledPreference() {
        let model = makeModel(isEnabled: true)
        model.send(.settingsChoiceSelected(.startFromNotification))
        XCTAssertEqual(preference.savedValues.last, false)
        XCTAssertFalse(preference.isEnabled)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startFromNotification)
    }

    /// 選択中と同じ値を選び直しても値は変わりません。
    ///
    /// 責務: オン・オフそれぞれで同じ選択肢を選び直した後も保存値と表示が元のままであることを確認します。
    func testReselectingSameChoiceKeepsValue() {
        let disabled = makeModel(isEnabled: false)
        disabled.send(.settingsChoiceSelected(.startFromNotification))
        XCTAssertFalse(preference.isEnabled)
        XCTAssertEqual(disabled.state.settingsSection.selectedChoice, .startFromNotification)

        let enabled = makeModel(isEnabled: true)
        enabled.send(.settingsChoiceSelected(.startAutomatically))
        XCTAssertTrue(preference.isEnabled)
        XCTAssertEqual(enabled.state.settingsSection.selectedChoice, .startAutomatically)
    }

    /// 表示は保存要求の値ではなく、保存後に読み直した値を反映します。
    ///
    /// 責務: 保存しても値が変わらない保存境界では、オンを選んでも表示がオフのままになることを確認します。
    func testSettingsChoiceDisplaysValueReadBackAfterSave() {
        let stub = AutomaticRecordingPreferenceSaveIgnoringStub(storedValue: false)
        let model = AutomaticRecordingPreferenceModel(
            preference: AutomaticRecordingPreferenceUseCase(preferencePort: stub),
            promptCompletion: AutomaticRecordingChoicePromptCompletionUseCase(
                completionPort: AutomaticRecordingChoicePromptCompletionFake(isCompleted: true)
            )
        )
        model.send(.settingsChoiceSelected(.startAutomatically))
        XCTAssertEqual(stub.requestedValues, [true])
        XCTAssertFalse(model.state.isAutomaticRecordingEnabled)
        XCTAssertEqual(model.state.settingsSection.selectedChoice, .startFromNotification)
    }

    /// サインイン状態の通知は保存値を変えません。
    ///
    /// 責務: `signInStateChanged` で自動記録設定と表示済みフラグへの書き込みが起きないことを確認します。
    func testSignInStateChangeDoesNotWritePreferences() {
        let model = makeModel(isEnabled: false, isCompleted: false)
        model.send(.signInStateChanged(isSignedIn: true))
        model.send(.signInStateChanged(isSignedIn: false))
        XCTAssertTrue(preference.savedValues.isEmpty)
        XCTAssertEqual(completion.markCount, 0)
    }
}
