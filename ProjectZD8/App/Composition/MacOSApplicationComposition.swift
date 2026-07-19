#if os(macOS)
import AppKit
import AuthenticationServices

/// macOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum MacOSApplicationComposition {
    /// iCloud同期とローカル保持を注入したアカウント設定モデルを生成します。
    ///
    /// 責務: macOSの軽量設定保存実装をSettingsユースケースとアカウント設定状態へ結び付けます。
    /// - Returns: Connectionを除く設定をアカウント単位で保持するモデル。
    static func makeAccountSettingsModel() -> AccountSettingsModel {
        AccountSettingsModel(
            settings: AccountSettings(),
            useCase: AccountSettingsUseCase(
                store: UbiquitousKeyValueStoreAccountSettingsStore()
            )
        )
    }

    /// 実Apple認証とKeychain保存を注入した認証セッションモデルを生成します。
    ///
    /// 責務: macOS表示ウインドウ、Apple認証、Keychain保存をAuthenticationユースケースへ結び付けます。
    /// - Returns: 実Appleアカウント認証を使用する認証セッションモデル。
    static func makeAuthenticationSessionModel() -> AuthenticationSessionModel {
        let authorization = AuthenticationServicesAppleAccountAuthorizationClient {
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first(where: \.isVisible)
        }
        let sessionStore = KeychainAuthenticationSessionStore()
        let accountSettingsStore = UbiquitousKeyValueStoreAccountSettingsStore()
        let defaultAdapterStore = UserDefaultsDefaultAdapterPreferenceStore()
        let sessionRevocation = UbiquitousKeyValueStoreAccountSessionRevocationStore()
        let dataEraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: accountSettingsStore,
            defaultAdapterStore: defaultAdapterStore
        )
        return AuthenticationSessionModel(
            state: initialAuthenticationState,
            restoreSession: RestoreAuthenticationSessionUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore
            ),
            signInWithApple: SignInWithAppleUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore
            ),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: sessionRevocation,
                dataEraser: dataEraser,
                sessionStore: sessionStore
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(
                dataEraser: dataEraser,
                sessionStore: sessionStore
            ),
            sessionRevocation: sessionRevocation
        )
    }

    /// 実デバイス探索とConnection設定保存を注入した設定プレゼンテーションモデルを生成します。
    ///
    /// 責務: macOSの探索・保存実装をDeviceConnectionユースケースと設定表示境界へ結び付けます。
    /// - Returns: 実際のシステム探索とデフォルト設定保存を使用するmacOS設定プレゼンテーションモデル。
    static func makeSettingsPresentationModel() -> MacOSSettingsPresentationModel {
        let discovery = MacOSSystemAdapterDiscovery()
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: discovery)
        let latestDiscovery = LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters)
        let preferenceStore = UserDefaultsDefaultAdapterPreferenceStore()
        return MacOSSettingsPresentationModel(
            state: MacOSSettingsState(),
            latestDiscovery: latestDiscovery,
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: preferenceStore
            )
        )
    }

    /// Debug UIテストが要求した認証済み起動状態または通常の確認中状態です。
    private static var initialAuthenticationState: AuthenticationState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-authenticated") {
            return AuthenticationState(
                phase: .signedIn,
                session: AppleAccountSession(userIdentifier: "ui-test-apple-account")
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-signed-out") {
            return AuthenticationState(phase: .signedOut)
        }
        #endif
        return AuthenticationState()
    }
}
#endif
