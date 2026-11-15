import Observation

/// 自動記録設定と記録開始方法の選択画面の操作を保存と表示状態へ変換します。
@MainActor
@Observable
final class AutomaticRecordingPreferenceModel {
    /// 設定画面と選択画面が描画する現在の状態です。
    private(set) var state: AutomaticRecordingPreferenceState

    /// 自動記録設定の読み書きを行うユースケースです。
    @ObservationIgnored
    private let preference: AutomaticRecordingPreferenceUseCase

    /// 選択画面の表示済みフラグを読み書きするユースケースです。
    @ObservationIgnored
    private let promptCompletion: AutomaticRecordingChoicePromptCompletionUseCase

    /// ユースケースを注入し、保存済みの値を読み込んで生成します。
    ///
    /// 責務: 自動記録設定と表示済みフラグの保存値を初期状態へ反映します。サインイン状態は未サインインで始めます。
    /// - Parameters:
    ///   - preference: 自動記録設定の読み書きを行うユースケース。
    ///   - promptCompletion: 選択画面の表示済みフラグを読み書きするユースケース。
    init(
        preference: AutomaticRecordingPreferenceUseCase,
        promptCompletion: AutomaticRecordingChoicePromptCompletionUseCase
    ) {
        self.preference = preference
        self.promptCompletion = promptCompletion
        state = AutomaticRecordingPreferenceState(
            isAutomaticRecordingEnabled: preference.load(),
            isChoicePromptCompleted: promptCompletion.isCompleted(),
            isSignedIn: false
        )
    }

    /// 受け取った操作を保存と表示状態へ反映します。
    ///
    /// 責務: 1件の操作を対応する保存要求と状態遷移へ振り分けます。
    /// - Parameter action: App層、設定画面、または選択画面から通知された型付き操作。
    func send(_ action: AutomaticRecordingPreferenceAction) {
        switch action {
        case let .signInStateChanged(isSignedIn):
            state.isSignedIn = isSignedIn
        case let .settingsChoiceSelected(choice):
            save(choice)
        case let .promptChoiceSelected(choice):
            save(choice)
            promptCompletion.markCompleted()
            state.isChoicePromptCompleted = promptCompletion.isCompleted()
        }
    }

    /// 選択肢を自動記録設定として保存し、保存後の値を状態へ反映します。
    ///
    /// 責務: 1件の選択肢を保存し、保存境界から読み直した値だけを表示へ使います。
    /// - Parameter choice: 保存する選択肢。
    private func save(_ choice: AutomaticRecordingChoice) {
        preference.save(choice.isAutomaticRecordingEnabled)
        state.isAutomaticRecordingEnabled = preference.load()
    }
}
