#if os(macOS)
import AppKit
import AuthenticationServices

/// macOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum MacOSApplicationComposition {
    /// PID定義DBとEXシリアル読取を結び付けます。
    ///
    /// 責務: macOSのPID定義永続化とOBDLink EX読取実装をLiveTelemetry状態へ注入します。
    /// - Returns: DB登録済みPIDを読み取れるモデル。
    /// - Parameter sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    static func makeLiveTelemetryModel(
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in }
    ) -> LiveTelemetryModel {
        LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: makeOBDPIDDefinitionRepository(),
                telemetry: DemoAwareOBDPIDTelemetryAdapter(
                    live: OBDLinkEXPIDTelemetryAdapter { endpoint in
                        MacOS115200BaudOBDSerialTransport(devicePath: endpoint.systemIdentifier)
                    },
                    demo: DemoOBDPIDTelemetryAdapter()
                )
            ),
            sessionDidEnd: sessionDidEnd
        )
    }

    /// 製品PID DBを開き、確認済みseedを非破壊登録します。
    ///
    /// 責務: macOSのPID定義永続化を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Returns: seed登録済みPID Repository。準備失敗時は利用不能Repository。
    private static func makeOBDPIDDefinitionRepository() -> any OBDPIDDefinitionRepository {
        do {
            let repository = try GRDBOBDPIDDefinitionRepository.openApplicationRepository()
            try StandardOBDPIDSeed.install(into: repository)
            return repository
        } catch {
            return UnavailableOBDPIDDefinitionRepository()
        }
    }

    /// CloudKit同期と選択済みシリアルアダプター通信を注入した車両管理モデルを生成します。
    ///
    /// 責務: macOSの車両保存、写真読込、シリアル識別をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    /// - Parameter connectionVehicleDidResolve: 接続対象車両をLoggingへ通知する処理。
    static func makeVehicleManagementModel(
        connectionVehicleDidResolve: @escaping @MainActor (VehicleProfile) -> Void = { _ in }
    ) -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: CloudKitVehicleRepository(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoAwareVehicleIdentificationAdapter(
                    live: SerialELMVehicleIdentificationAdapter { endpoint in
                        MacOS115200BaudOBDSerialTransport(devicePath: endpoint.systemIdentifier)
                    },
                    demo: DemoVehicleIdentificationAdapter()
                )
            ),
            photoImporter: VehiclePhotoFileImporter(),
            connectionVehicleDidResolve: connectionVehicleDidResolve
        )
    }

    /// 製品用の接続セッション保存先を生成します。
    ///
    /// 責務: macOSの接続履歴を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Returns: Application Support内の接続セッション保存先。
    static func makeConnectionSessionRepository() -> any ConnectionSessionRepository {
        (try? GRDBConnectionSessionRepository.openApplicationRepository())
            ?? UnavailableConnectionSessionRepository()
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
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: MacOSSystemAdapterDiscovery(),
            demoCandidate: DemoOBDAdapter.candidate
        )
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
