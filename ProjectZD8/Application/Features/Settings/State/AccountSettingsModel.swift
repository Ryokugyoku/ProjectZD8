import Observation

/// アカウント設定操作を保存、復元、端末間同期へ変換します。
@MainActor
@Observable
final class AccountSettingsModel {
    /// ルート画面と設定画面が描画する現在の設定です。
    var settings: AccountSettings

    /// アカウント設定の保存、復元、同期監視を行うユースケースです。
    @ObservationIgnored
    private let useCase: AccountSettingsUseCase

    /// 現在設定を読み書きするAppleユーザー識別子です。
    @ObservationIgnored
    private var accountIdentifier: String?

    /// 初期設定とユースケースを注入してモデルを生成します。
    ///
    /// 責務: アカウント設定の状態遷移を保存と同期のユースケースへ結び付けます。
    /// - Parameters:
    ///   - settings: アカウント確定前に表示する初期設定。
    ///   - useCase: 設定の保存、復元、同期監視を行うユースケース。
    init(
        settings: AccountSettings,
        useCase: AccountSettingsUseCase
    ) {
        self.settings = settings
        self.useCase = useCase
    }

    /// 受け取った設定操作をアカウント状態または保存済み設定へ反映します。
    ///
    /// 責務: 1件のアカウント設定操作を対応する状態遷移と保存要求へ変換します。
    /// - Parameter action: App層または設定画面から通知された型付き操作。
    func send(_ action: AccountSettingsAction) {
        switch action {
        case let .accountIdentifierChanged(identifier):
            activateAccount(identifier)
        case let .languageSelected(language):
            settings.language = language
            saveIfAccountIsActive()
        case let .appearanceSelected(appearance):
            settings.appearance = appearance
            saveIfAccountIsActive()
        case let .automaticSessionUploadChanged(isEnabled):
            settings.automaticSessionUploadEnabled = isEnabled
            saveIfAccountIsActive()
        }
    }

    /// 指定されたアカウントへ保存・同期スコープを切り替えます。
    ///
    /// 責務: 以前の監視を終了して現在のアカウント設定だけを復元および購読します。
    /// - Parameter identifier: 新しいAppleユーザー識別子。未認証の場合は `nil`。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        useCase.stopObserving()
        accountIdentifier = identifier

        guard let identifier, !identifier.isEmpty else {
            settings = AccountSettings()
            return
        }

        settings = useCase.load(for: identifier)
        useCase.startObserving(for: identifier) { [weak self] synchronizedSettings in
            self?.settings = synchronizedSettings
        }
    }

    /// 認証済みアカウントが存在する場合だけ現在設定を保存します。
    ///
    /// 責務: 現在の表示設定とセッション自動送信設定を有効な1件のアカウントスコープへ保存します。
    private func saveIfAccountIsActive() {
        guard let accountIdentifier else { return }
        useCase.save(settings, for: accountIdentifier)
    }
}
