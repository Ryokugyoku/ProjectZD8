#if os(iOS)
import AuthenticationServices
import UIKit

/// iOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum IOSApplicationComposition {
    /// PID定義DBとiOSデモBluetooth読取境界を結び付けます。
    ///
    /// 責務: iOSのPID定義永続化をデモ対応かつ実BLE未提供のLiveTelemetry構成へ注入します。
    /// - Returns: デモBluetoothで継続取得でき、実BLEでは明示的利用不能を返すモデル。
    /// - Parameter sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    /// - Parameter odometerDidChange: 累積走行距離をLoggingへ通知する処理。
    static func makeLiveTelemetryModel(
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in },
        odometerDidChange: @escaping @MainActor (Double) -> Void = { _ in }
    ) -> LiveTelemetryModel {
        let telemetry = DemoAwareOBDPIDTelemetryAdapter(
            live: UnavailableOBDPIDTelemetryAdapter(),
            demo: DemoOBDPIDTelemetryAdapter()
        )
        return LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: makeOBDPIDDefinitionRepository(),
                telemetry: telemetry
            ),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: makeVehiclePIDCapabilityRepository(), telemetry: telemetry
            ),
            sessionDidEnd: sessionDidEnd,
            odometerDidChange: odometerDidChange
        )
    }

    /// 製品PID DBを開き、確認済みseedを非破壊登録します。
    ///
    /// 責務: iOSのPID定義永続化を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Returns: seed登録済みPID Repository。準備失敗時は利用不能Repository。
    static func makeOBDPIDDefinitionRepository() -> any OBDPIDDefinitionRepository {
        do {
            let repository = try GRDBOBDPIDDefinitionRepository.openApplicationRepository()
            try StandardOBDPIDSeed.install(into: repository)
            return repository
        } catch {
            return UnavailableOBDPIDDefinitionRepository()
        }
    }

    /// 製品DBの車両別対応PID保存先を生成します。
    ///
    /// 責務: iOSの車両別対応PID永続化を利用可能または明示的利用不能境界へ変換します。
    /// - Returns: 車両別対応PID Repository。
    static func makeVehiclePIDCapabilityRepository() -> any VehiclePIDCapabilityRepository {
        (try? GRDBVehiclePIDCapabilityRepository.openApplicationRepository())
            ?? UnavailableVehiclePIDCapabilityRepository()
    }

    /// CloudKit同期とデモBluetooth識別境界を注入した車両管理モデルを生成します。
    ///
    /// 責務: iOSの車両保存とデモ対応かつ実BLE未提供の識別境界をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    /// - Parameter connectionVehicleDidResolve: 接続対象車両をLoggingへ通知する処理。
    static func makeVehicleManagementModel(
        connectionVehicleDidResolve: @escaping @MainActor (VehicleProfile, OBDConnectionEndpoint) -> Void = { _, _ in }
    ) -> VehicleManagementModel {
        VehicleManagementModel(
            state: VehicleManagementState(),
            repository: CloudKitVehicleRepository(),
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoAwareVehicleIdentificationAdapter(
                    live: UnavailableVehicleIdentificationAdapter(error: .transportUnsupported),
                    demo: DemoVehicleIdentificationAdapter()
                )
            ),
            photoImporter: VehiclePhotoFileImporter(),
            pidCapabilityRepository: makeVehiclePIDCapabilityRepository(),
            pidDefinitionRepository: makeOBDPIDDefinitionRepository(),
            connectionVehicleDidResolve: connectionVehicleDidResolve
        )
    }

    /// 製品用の接続セッション保存先を生成します。
    ///
    /// 責務: iOSの接続履歴を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Returns: Application Support内の接続セッション保存先。
    static func makeConnectionSessionRepository() -> any ConnectionSessionRepository {
        (try? GRDBConnectionSessionRepository.openApplicationRepository())
            ?? UnavailableConnectionSessionRepository()
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
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: IOSCoreBluetoothAdapterDiscovery(),
            demoCandidates: DemoOBDAdapter.bluetoothCandidates
        )
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
