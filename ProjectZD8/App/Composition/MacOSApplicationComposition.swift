#if os(macOS)
import AppKit
import AuthenticationServices

/// macOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum MacOSApplicationComposition {
    /// 検証済み2種の主要PIDとEXシリアル読取を結び付けます。
    ///
    /// 責務: macOSの主要PID定義とOBDLink EX読取実装をLiveTelemetry状態へ注入します。
    /// - Returns: 冷却水温とエンジン回転数を読み取れるモデル。
    static func makeLiveTelemetryModel() -> LiveTelemetryModel {
        LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitions: StandardOBDPIDSeed.definitions,
                telemetry: OBDLinkEXPIDTelemetryAdapter { endpoint in
                    MacOSOBDLinkEXSerialTransport(devicePath: endpoint.systemIdentifier)
                }
            )
        )
    }

    /// CloudKit同期、PID DB、OBDLink EX通信を注入した車両管理モデルを生成します。
    ///
    /// 責務: macOSの車両保存、写真読込、PID DB、EXシリアル識別をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    static func makeVehicleManagementModel() -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: CloudKitVehicleRepository(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: makeVehicleIdentificationAdapter()
            ),
            photoImporter: VehiclePhotoFileImporter()
        )
    }

    /// PID専用DBを準備してOBDLink EX識別Adapterを生成します。
    ///
    /// 責務: PIDスキーマ準備結果をmacOS EX製品通信または明示的利用不能へ変換します。
    /// - Returns: PID DBが利用可能なEX識別Adapter。準備失敗時は型付き利用不能境界。
    private static func makeVehicleIdentificationAdapter() -> any VehicleIdentificationPort {
        do {
            let repository = try GRDBOBDPIDDefinitionRepository.openApplicationRepository()
            try StandardOBDPIDSeed.install(into: repository)
            return OBDLinkEXVehicleIdentificationAdapter { endpoint in
                MacOSOBDLinkEXSerialTransport(devicePath: endpoint.systemIdentifier)
            }
        } catch {
            return UnavailableVehicleIdentificationAdapter(error: .pidCatalogUnavailable)
        }
    }

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
