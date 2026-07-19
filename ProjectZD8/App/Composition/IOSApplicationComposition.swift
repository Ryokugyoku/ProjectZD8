#if os(iOS)
import AuthenticationServices
import UIKit

/// iOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum IOSApplicationComposition {
    /// iOSで未提供の実PID読取を明示的利用不能境界へ結び付けます。
    ///
    /// 責務: iOSのLiveTelemetryが未検証のBLE成功を表示しない構成を生成します。
    /// - Returns: 読取要求時に明示的利用不能を返すモデル。
    static func makeLiveTelemetryModel() -> LiveTelemetryModel {
        LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitions: StandardOBDPIDSeed.definitions,
                telemetry: UnavailableOBDPIDTelemetryAdapter()
            )
        )
    }

    /// CloudKit同期とEX非対応境界を注入した車両管理モデルを生成します。
    ///
    /// 責務: iOSの車両保存、写真読込、USB専用EXの非対応境界をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    static func makeVehicleManagementModel() -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: CloudKitVehicleRepository(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: UnavailableVehicleIdentificationAdapter(error: .transportUnsupported)
            ),
            photoImporter: VehiclePhotoFileImporter()
        )
    }

    /// iCloud同期とローカル保持を注入したアカウント設定モデルを生成します。
    ///
    /// 責務: iOSの軽量設定保存実装をSettingsユースケースとアカウント設定状態へ結び付けます。
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
    /// 責務: iOS表示ウインドウ、Apple認証、Keychain保存をAuthenticationユースケースへ結び付けます。
    /// - Returns: 実Appleアカウント認証を使用する認証セッションモデル。
    static func makeAuthenticationSessionModel() -> AuthenticationSessionModel {
        let authorization = AuthenticationServicesAppleAccountAuthorizationClient {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
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

    /// 実CoreBluetooth探索とConnection設定保存を注入した設定プレゼンテーションモデルを生成します。
    ///
    /// 責務: iOSの探索・保存実装をDeviceConnectionユースケースと設定表示境界へ結び付けます。
    /// - Returns: 実際のBLE探索とデフォルト設定保存を使用するiOS設定プレゼンテーションモデル。
    static func makeSettingsPresentationModel() -> IOSSettingsPresentationModel {
        let discovery = IOSCoreBluetoothAdapterDiscovery()
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: discovery)
        let latestDiscovery = LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters)
        let preferenceStore = UserDefaultsDefaultAdapterPreferenceStore()
        return IOSSettingsPresentationModel(
            state: IOSSettingsState(),
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
