#if os(iOS)
import SwiftUI

/// iOSアプリケーション専用のルートレイアウトを描画します。
struct IOSAppShellView: View {
    /// iOSシェルが現在表示している遷移先です。
    @State private var selectedDestination: IOSAppShellDestination = .home

    /// Connectionを除くアカウント同期対象設定を提供するモデルです。
    let accountSettingsModel: AccountSettingsModel

    /// Bluetoothアダプター選択状態を画面操作へ変換するモデルです。
    let settingsModel: IOSSettingsPresentationModel

    /// Authenticationが管理するアカウント削除の現在段階です。
    let accountDeletionPhase: AccountDeletionPhase

    /// Authenticationが保持する直近のアカウント削除失敗です。
    let accountDeletionFailure: AccountDeletionFailure?

    /// アカウント削除の型付き操作をAuthenticationへ通知します。
    let sendAuthenticationAction: (AuthenticationAction) -> Void

    /// アカウント設定モデルとConnection設定モデルを注入してiOSルート画面を生成します。
    ///
    /// 責務: iOS AppShellを同期対象とConnection固有の独立した設定モデルへ結び付けます。
    /// - Parameters:
    ///   - accountSettingsModel: 言語と外観を提供するアカウント設定モデル。
    ///   - settingsModel: Bluetooth候補選択状態を提供するモデル。
    ///   - accountDeletionPhase: アカウント削除の現在段階。
    ///   - accountDeletionFailure: 直近のアカウント削除失敗。
    ///   - sendAuthenticationAction: アカウント削除操作の通知先。
    init(
        accountSettingsModel: AccountSettingsModel,
        settingsModel: IOSSettingsPresentationModel,
        accountDeletionPhase: AccountDeletionPhase,
        accountDeletionFailure: AccountDeletionFailure?,
        sendAuthenticationAction: @escaping (AuthenticationAction) -> Void
    ) {
        self.accountSettingsModel = accountSettingsModel
        self.settingsModel = settingsModel
        self.accountDeletionPhase = accountDeletionPhase
        self.accountDeletionFailure = accountDeletionFailure
        self.sendAuthenticationAction = sendAuthenticationAction
    }

    /// iPhone向けのコンテンツ領域と下部ナビゲーションを提供します。
    ///
    /// 責務: 選択中の遷移先と表示設定を使ってiOS AppShellを描画します。
    var body: some View {
        appearanceAppliedContent
    }

    /// 選択した外観がシステム追従へ戻せる状態でiOSシェルへ適用された表示です。
    @ViewBuilder
    private var appearanceAppliedContent: some View {
        switch accountSettingsModel.settings.appearance {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }

    /// 言語と外観を適用する前のiOSシェル本体です。
    private var content: some View {
        ZStack {
            IOSAppShellBackground()

            IOSDestinationView(
                destination: selectedDestination,
                settingsState: settingsModel.state,
                accountSettings: accountSettingsModel.settings,
                sendHomeAction: handleHomeAction,
                sendSettingsAction: settingsModel.send,
                sendAccountSettingsAction: accountSettingsModel.send,
                accountDeletionPhase: accountDeletionPhase,
                accountDeletionFailure: accountDeletionFailure,
                sendAuthenticationAction: sendAuthenticationAction
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOSAppShellTabBar(selection: $selectedDestination)
        }
        .environment(\.locale, Locale(identifier: accountSettingsModel.settings.language.localeIdentifier))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-app-shell")
    }

    /// HOMEから受け取った1件の操作をiOSナビゲーションへ反映します。
    ///
    /// 責務: HOMEのアダプター設定要求を設定タブへの遷移と注目要求へ変換します。
    /// - Parameter action: HOMEから通知された型付き操作。
    private func handleHomeAction(_ action: IOSHomeAction) {
        switch action {
        case .adapterSetupRequested:
            selectedDestination = .settings
            settingsModel.send(.adapterAttentionRequested)
        }
    }
}
#endif
