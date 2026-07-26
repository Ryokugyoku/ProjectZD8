#if os(iOS)
import AuthenticationServices
import UIKit

/// iOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum IOSApplicationComposition {
    /// PID定義DB、iOS Bluetooth読取境界、接続中の画面自動ロック抑止を結び付けます。
    ///
    /// 責務: iOSのPID取得依存関係と接続中の画面自動ロック抑止を1件のLiveTelemetry構成へ注入します。
    /// - Returns: デモ、既知BLE UART、または構成済みBluetooth Classic終端で取得できるモデル。
    /// - Parameter sessionDidEnd: PID取得終了原因をLoggingへ通知する処理。
    /// - Parameter distanceDidChange: 取得元付き累積距離をLoggingへ通知する処理。
    /// - Parameter rawResponseDidReceive: 数値化前のOBD応答をLoggingへ保存する処理。
    static func makeLiveTelemetryModel(
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason) -> Void = { _ in },
        distanceDidChange: @escaping @MainActor (ConnectionSessionDistanceObservation) -> Void = { _ in },
        rawResponseDidReceive: @escaping @Sendable (OBDRawResponseObservation) async throws -> Void = { _ in }
    ) -> LiveTelemetryModel {
        let externalAccessoryConfiguration = IOSExternalAccessoryProtocolConfiguration()
        let telemetry = DemoAwareOBDPIDTelemetryAdapter(
            live: OBDLinkEXPIDTelemetryAdapter { endpoint in
                try makeBluetoothOBDTransport(
                    for: endpoint,
                    configuration: externalAccessoryConfiguration
                )
            },
            demo: DemoOBDPIDTelemetryAdapter()
        )
        let definitionRepository = makeOBDPIDDefinitionRepository()
        return LiveTelemetryModel(
            readMajorPIDs: ReadMajorOBDPIDsUseCase(
                definitionRepository: definitionRepository,
                telemetry: telemetry,
                rawResponseDidReceive: rawResponseDidReceive
            ),
            loadVehicleCapabilities: LoadVehiclePIDCapabilitiesUseCase(
                repository: makeVehiclePIDCapabilityRepository(),
                telemetry: telemetry,
                definitionRepository: definitionRepository
            ),
            sessionDidEnd: sessionDidEnd,
            distanceDidChange: distanceDidChange,
            systemSleepInhibitor: IOSVehicleConnectionScreenSleepInhibitor()
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
            try ZD8OBDPIDSeed.install(into: repository)
            return repository
        } catch {
            return UnavailableOBDPIDDefinitionRepository()
        }
    }

    /// 製品DBの車両別対応PID保存先を生成します。
    ///
    /// 責務: iOSの車両別対応PID永続化を利用可能または明示的利用不能境界へ変換します。
    /// - Returns: 車両別対応PID Repository。
    static func makeVehiclePIDCapabilityRepository() -> any VehiclePIDCapabilityRepository & AccountVehiclePIDCapabilityErasureRepository {
        (try? GRDBVehiclePIDCapabilityRepository.openApplicationRepository())
            ?? UnavailableVehiclePIDCapabilityRepository()
    }

    /// CloudKit同期とiOS Bluetooth識別境界を注入した車両管理モデルを生成します。
    ///
    /// 責務: iOSの車両保存とデモまたは既知Bluetooth UART識別境界をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    /// - Parameter connectionSessionRepository: Garageの車両別ログ集計に使用する接続履歴取得先。
    /// - Parameter vehicleSessionsDidDelete: 車両関連セッション削除後に履歴表示へ再読込を通知する処理。
    /// - Parameter connectionVehicleDidResolve: 接続対象車両、終端、OBD識別観測をLoggingと監視開始へ通知する処理。
    static func makeVehicleManagementModel(
        connectionSessionRepository: any ConnectionSessionRepository & ConnectionSessionErasureRepository,
        vehicleSessionsDidDelete: @escaping @MainActor () -> Void = {},
        connectionVehicleDidResolve: @escaping @MainActor (
            VehicleProfile,
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _, _ in }
    ) -> VehicleManagementModel {
        let vehicleRepository = CloudKitVehicleRepository()
        let externalAccessoryConfiguration = IOSExternalAccessoryProtocolConfiguration()
        return VehicleManagementModel(
            state: VehicleManagementState(),
            repository: vehicleRepository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoAwareVehicleIdentificationAdapter(
                    live: SerialELMVehicleIdentificationAdapter { endpoint in
                        try makeBluetoothOBDTransport(
                            for: endpoint,
                            configuration: externalAccessoryConfiguration
                        )
                    },
                    demo: DemoVehicleIdentificationAdapter()
                )
            ),
            photoImporter: VehiclePhotoFileImporter(),
            pidCapabilityRepository: makeVehiclePIDCapabilityRepository(),
            pidDefinitionRepository: makeOBDPIDDefinitionRepository(),
            loadVehicleActivitySummaries: LoadVehicleActivitySummariesUseCase(
                repository: connectionSessionRepository
            ),
            deleteVehicleWithSessions: DeleteVehicleWithSessionsUseCase(
                sessionRepository: connectionSessionRepository,
                localSessionErasureRepository: connectionSessionRepository,
                sessionTransferRepository: CloudKitConnectionSessionTransferRepository(),
                vehicleRepository: vehicleRepository
            ),
            vehicleSessionsDidDelete: vehicleSessionsDidDelete,
            connectionVehicleDidResolve: connectionVehicleDidResolve
        )
    }

    /// GRDBとCloudKitを注入したiPhone向け整備モデルを生成します。
    ///
    /// 責務: iPhoneの車両別整備保存、写真取込、端末間同期をMaintenanceへ結び付けます。
    /// - Returns: オフライン保存とCloudKit双方向同期を使用する整備モデル。
    static func makeMaintenanceModel() -> MaintenanceModel {
        let repository: any MaintenanceRecordRepository =
            (try? GRDBMaintenanceRecordRepository.openApplicationRepository())
            ?? UnavailableMaintenanceRecordRepository()
        return MaintenanceModel(
            state: MaintenanceState(),
            repository: repository,
            synchronize: SynchronizeMaintenanceRecordsUseCase(
                localRepository: repository,
                remoteStore: CloudKitMaintenanceRemoteStore()
            ),
            photoImporter: MaintenancePhotoFileImporter()
        )
    }

    /// 製品用の接続セッション保存先を生成します。
    ///
    /// 責務: iOSの接続履歴を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Returns: Application Support内の接続セッション保存先。
    static func makeConnectionSessionRepository() -> any ConnectionSessionRepository & ConnectionSessionRawLogRepository & ConnectionSessionErasureRepository & AccountConnectionSessionErasureRepository {
        (try? GRDBConnectionSessionRepository.openApplicationRepository())
            ?? UnavailableConnectionSessionRepository()
    }

    /// 現在のiOS端末を新規セッションの取得元表示へ変換します。
    ///
    /// 責務: 現在の端末種別とユーザー設定名を1件の取得元端末スナップショットとして生成します。
    /// - Returns: iPhoneまたはiPadの種別と現在端末名。
    static func makeConnectionSessionAcquisitionDevice() -> ConnectionSessionAcquisitionDevice {
        let device = UIDevice.current
        let platform: ConnectionSessionAcquisitionPlatform = device.userInterfaceIdiom == .pad ? .iPad : .iPhone
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConnectionSessionAcquisitionDevice(
            platform: platform,
            name: name.isEmpty ? device.model : name
        )
    }

    /// iPhone向けセッション同期ユースケースを生成します。
    ///
    /// 責務: iPhoneのローカルセッション概要とRaw保管をCloudKit双方向同期へ結び付けます。
    /// - Parameter storage: 接続履歴とRawログを保持する共通ローカル保存先。
    /// - Returns: iPhoneで概要を送受信しRawをCloudKitへ保管する同期ユースケース。
    static func makeConnectionSessionSynchronization(
        storage: any ConnectionSessionRepository & ConnectionSessionRawLogRepository & ConnectionSessionErasureRepository
    ) -> SynchronizeConnectionSessionsUseCase {
        SynchronizeConnectionSessionsUseCase(
            sessionRepository: storage,
            rawLogRepository: storage,
            sessionErasureRepository: storage,
            transferRepository: CloudKitConnectionSessionTransferRepository(),
            role: .iPhone
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
    /// - Parameter connectionSessionStorage: アカウント削除時に接続履歴とRawログを消去する共通保存先。
    /// - Returns: 実Appleアカウント認証を使用する認証セッションモデル。
    static func makeAuthenticationSessionModel(
        connectionSessionStorage: any AccountConnectionSessionErasureRepository
    ) -> AuthenticationSessionModel {
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
        let vehicleDataEraser = CloudKitVehicleRepository()
        let vehiclePIDCapabilityEraser = makeVehiclePIDCapabilityRepository()
        let dataEraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: accountSettingsStore,
            defaultAdapterStore: defaultAdapterStore,
            connectionSessionStorage: connectionSessionStorage,
            vehicleDataEraser: vehicleDataEraser,
            vehiclePIDCapabilityEraser: vehiclePIDCapabilityEraser
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
                sessionTransfers: CloudKitConnectionSessionTransferRepository(),
                vehicleDataEraser: vehicleDataEraser,
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

    /// iOS Bluetooth探索とConnection設定保存を注入した設定プレゼンテーションモデルを生成します。
    ///
    /// 責務: iOSの探索・保存実装をDeviceConnectionユースケースと設定表示境界へ結び付けます。
    /// - Returns: 接続済みExternalAccessoryとBLE探索およびデフォルト設定保存を使用するモデル。
    static func makeSettingsPresentationModel() -> IOSSettingsPresentationModel {
        let externalAccessoryConfiguration = IOSExternalAccessoryProtocolConfiguration()
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: IOSBluetoothAdapterDiscovery(
                externalAccessoryConfiguration: externalAccessoryConfiguration
            ),
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

    /// 既定BLE到来監視とユーザー承認付きローカル通知を生成します。
    ///
    /// 責務: iOSのCoreBluetooth監視と通知応答を既定アダプター接続確認ユースケースへ注入します。
    /// - Parameter connectionRequested: 通知で了承されたBLE終端の通知先。
    /// - Returns: 保存済み既定BLEを監視して接続確認を提示するユースケース。
    static func makeDefaultAdapterConnectionPromptUseCase(
        connectionRequested: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) -> PromptForDefaultAdapterConnectionUseCase {
        PromptForDefaultAdapterConnectionUseCase(
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: UserDefaultsDefaultAdapterPreferenceStore()
            ),
            arrivalMonitor: IOSCoreBluetoothDefaultAdapterArrivalMonitor(),
            connectionPrompt: IOSLocalDefaultAdapterConnectionPrompt(),
            connectionRequested: connectionRequested
        )
    }

    /// 選択済みiOS Bluetooth終端に対応するELM/STNバイトストリームを生成します。
    ///
    /// 責務: 1件のBLEまたはBluetooth Classic終端を対応するOBDコマンドTransportへ変換します。
    /// - Parameters:
    ///   - endpoint: 選択済みアダプターの物理終端。
    ///   - configuration: Bluetooth Classic用にInfo.plistから読み取ったExternalAccessoryプロトコル許可集合。
    /// - Returns: 選択済み終端のELM/STN連続バイト通信に使用するTransport。
    /// - Throws: 未構成、対象外Transport、UUID不正、または通信生成条件を満たさない場合の識別エラー。
    private static func makeBluetoothOBDTransport(
        for endpoint: OBDConnectionEndpoint,
        configuration: IOSExternalAccessoryProtocolConfiguration
    ) throws -> any OBDCommandTransport {
        switch endpoint.transport {
        case .bluetoothLowEnergy:
            return try AppleCoreBluetoothOBDTransport(endpoint: endpoint)
        case .bluetoothClassic:
            return try IOSExternalAccessoryOBDTransport(
                endpoint: endpoint,
                configuration: configuration
            )
        case .serial:
            throw VehicleIdentificationError.transportUnsupported
        }
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
