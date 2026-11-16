#if os(iOS)
import AuthenticationServices
import UIKit

/// iOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum IOSApplicationComposition: ApplicationPlatformComposing {
    /// iOSプロセスに1本だけ存在する常駐BLEリンク一式です。
    ///
    /// 常駐リンク監視・車両識別・PID継続取得が同じリンクとバイトストリームを共有するため、最初の参照時に1回だけ生成します。
    static let residentLink = IOSResidentAdapterLink.make()

    /// PID定義DB、iOS Bluetooth読取境界、接続中の画面自動ロック抑止を結び付けます。
    ///
    /// 責務: iOSのPID取得依存関係と接続中の画面自動ロック抑止を1件のLiveTelemetry構成へ注入します。
    /// - Returns: デモ、既知BLE UART、または構成済みBluetooth Classic終端で取得できるモデル。
    /// - Parameter sessionDidEnd: PID取得終了原因と終了時刻(`nil` は処理時刻)をLoggingへ通知する処理。
    /// - Parameter distanceDidChange: 取得元付き累積距離をLoggingへ通知する処理。
    /// - Parameter database: PID定義と車両別対応PIDの保存先が共有する製品DB接続。
    /// - Parameter connectionSessionStorage: 同じGRDB Queueを共有する接続session・取得証拠・チャンク・区間・欠損の保存先。
    /// - Parameter activeSessionID: 現在Logging sessionの識別子を返す境界。
    /// - Parameter performanceEvents: 方式B取得区間を通知する匿名計測境界。
    ///
    /// BLE終端が常駐リンクの保持するアダプターなら、常駐リンク上のトランスポートを使います。
    static func makeLiveTelemetryModel(
        database: ApplicationDatabaseConnection,
        connectionSessionStorage: ConnectionSessionStorageDependencies,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort(),
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason, Date?) -> Void = { _, _ in },
        distanceDidChange: @escaping @MainActor (ConnectionSessionDistanceObservation) -> Void = { _ in }
    ) -> LiveTelemetryModel {
        let externalAccessoryConfiguration = IOSExternalAccessoryProtocolConfiguration()
        let residentLink = residentLink
        let live = OBDLinkEXPIDTelemetryAdapter { endpoint in
            try makeBluetoothOBDTransport(
                for: endpoint,
                configuration: externalAccessoryConfiguration,
                residentLink: residentLink,
                isTelemetry: true
            )
        }
        let telemetry = DemoAwareOBDPIDTelemetryAdapter(live: live, demo: DemoOBDPIDTelemetryAdapter())
        return LiveTelemetryModelAssembly.makeModel(
            telemetry: telemetry,
            linkRecovery: DemoAwareLiveTelemetryLinkRecoveryAdapter(live: live),
            definitionRepository: makeOBDPIDDefinitionRepository(database: database),
            capabilityRepository: makeVehiclePIDCapabilityRepository(database: database),
            storage: connectionSessionStorage,
            acquisitionPlatform: makeConnectionSessionAcquisitionDevice().platform,
            activeSessionID: activeSessionID,
            performanceEvents: performanceEvents,
            sessionDidEnd: sessionDidEnd,
            distanceDidChange: distanceDidChange,
            systemSleepInhibitor: IOSVehicleConnectionScreenSleepInhibitor(),
            acquisitionDiagnostics: OSLogLiveTelemetryAcquisitionDiagnosticsAdapter()
        )
    }

    /// 共有製品DB接続からPID定義保存先を生成し、確認済みseedを非破壊登録します。
    ///
    /// 責務: iOSのPID定義永続化を利用可能なGRDB実装または明示的利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: seed登録済みPID Repository。準備失敗時は元のエラーを診断へ残し、利用不能Repository。
    static func makeOBDPIDDefinitionRepository(
        database: ApplicationDatabaseConnection
    ) -> any OBDPIDDefinitionRepository {
        ProductDatabaseRepositoryFactory().makeOBDPIDDefinitionRepository(database: database)
    }

    /// 共有製品DB接続から車両別対応PID保存先を生成します。
    ///
    /// 責務: iOSの車両別対応PID永続化を利用可能または明示的利用不能境界へ変換します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 車両別対応PID Repository。準備失敗時は元のエラーを診断へ残し、利用不能Repository。
    static func makeVehiclePIDCapabilityRepository(
        database: ApplicationDatabaseConnection
    ) -> any VehiclePIDCapabilityRepository & AccountVehiclePIDCapabilityErasureRepository {
        ProductDatabaseRepositoryFactory().makeVehiclePIDCapabilityRepository(database: database)
    }

    /// CloudKit同期とiOS Bluetooth識別境界を注入した車両管理モデルを生成します。
    ///
    /// 責務: iOSの車両保存とデモまたは既知Bluetooth UART識別境界をVehicleManagementへ結び付けます。
    /// - Returns: private database同期を使用する車両管理モデル。
    /// - Parameter database: PID定義と車両別対応PIDの保存先が共有する製品DB接続。
    /// - Parameter connectionSessionRepository: Garageの車両別ログ集計に使用する接続履歴取得先。
    /// - Parameter vehicleSessionsDidDelete: 車両関連セッション削除後に履歴表示へ再読込を通知する処理。
    /// - Parameter connectionVehicleDidResolve: 接続対象車両、終端、OBD識別観測をLoggingと監視開始へ通知する処理。
    /// - Parameter unregisteredConnectionDidStart: 未登録車両の終端と識別観測を、車両なしの接続開始へ通知する処理。
    /// - Parameter unregisteredConnectionVehicleDidRegister: 車両なしの接続中に登録された車両をLoggingへ通知する処理。
    /// - Parameter vehicleDidRegister: 新規登録した車両とアカウント識別子を受け取り、観測VINの一致するセッションへ紐付ける処理。
    /// - Parameter connectionIdentificationWillBegin: 接続のための車両識別を始める直前に呼ぶ処理。
    /// - Parameter connectionIdentificationDidEnd: 接続のための車両識別が終わった時に呼ぶ処理。
    ///
    /// BLE終端が常駐リンクの保持するアダプターなら、常駐リンク上のトランスポートを使います。
    static func makeVehicleManagementModel(
        database: ApplicationDatabaseConnection,
        connectionSessionRepository: any ConnectionSessionRepository & ConnectionSessionErasureRepository,
        vehicleSessionsDidDelete: @escaping @MainActor () -> Void = {},
        connectionVehicleDidResolve: @escaping @MainActor (
            VehicleProfile,
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _, _ in },
        unregisteredConnectionDidStart: @escaping @MainActor (
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _ in },
        unregisteredConnectionVehicleDidRegister: @escaping @MainActor (VehicleProfile) -> Void = { _ in },
        vehicleDidRegister: @escaping @MainActor (VehicleProfile, String) throws -> Void = { _, _ in },
        connectionIdentificationWillBegin: @escaping @MainActor () -> Void = {},
        connectionIdentificationDidEnd: @escaping @MainActor () -> Void = {}
    ) -> VehicleManagementModel {
        let vehicleRepository = CloudKitVehicleRepository(
            accountDeletionCheck: AccountDeletionMarkerComposition.check
        )
        let residentLink = residentLink
        let externalAccessoryConfiguration = IOSExternalAccessoryProtocolConfiguration()
        return VehicleManagementModel(
            state: VehicleManagementState(),
            repository: vehicleRepository,
            identifyForConnection: IdentifyVehicleForConnectionUseCase(
                identification: DemoAwareVehicleIdentificationAdapter(
                    live: SerialELMVehicleIdentificationAdapter { endpoint in
                        try makeBluetoothOBDTransport(
                            for: endpoint,
                            configuration: externalAccessoryConfiguration,
                            residentLink: residentLink,
                            isTelemetry: false
                        )
                    },
                    demo: DemoVehicleIdentificationAdapter()
                )
            ),
            photoImporter: VehiclePhotoFileImporter(),
            pidCapabilityRepository: makeVehiclePIDCapabilityRepository(database: database),
            pidDefinitionRepository: makeOBDPIDDefinitionRepository(database: database),
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
            connectionVehicleDidResolve: connectionVehicleDidResolve,
            unregisteredConnectionDidStart: unregisteredConnectionDidStart,
            unregisteredConnectionVehicleDidRegister: unregisteredConnectionVehicleDidRegister,
            vehicleDidRegister: vehicleDidRegister,
            connectionIdentificationWillBegin: connectionIdentificationWillBegin,
            connectionIdentificationDidEnd: connectionIdentificationDidEnd
        )
    }

    /// GRDBとCloudKitを注入したiPhone向け整備モデルを生成します。
    ///
    /// 責務: iPhoneの車両別整備保存、写真取込、端末間同期をMaintenanceへ結び付けます。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: オフライン保存とCloudKit双方向同期を使用する整備モデル。DB準備失敗時は保存先が利用不能境界になります。
    static func makeMaintenanceModel(database: ApplicationDatabaseConnection) -> MaintenanceModel {
        let repository = ProductDatabaseRepositoryFactory().makeMaintenanceRecordRepository(database: database)
        return MaintenanceModel(
            state: MaintenanceState(),
            repository: repository,
            synchronize: SynchronizeMaintenanceRecordsUseCase(
                localRepository: repository,
                remoteStore: CloudKitMaintenanceRemoteStore(),
                accountDeletionCheck: AccountDeletionMarkerComposition.check
            ),
            photoImporter: MaintenancePhotoFileImporter()
        )
    }

    /// 明示測定buildだけに匿名signpost adapterを生成します。
    ///
    /// 責務: compile条件と外部run識別子をiOS取得性能event境界へ変換します。
    /// - Returns: 有効な測定条件ではsignpost adapter、それ以外はno-op境界。
    static func makeAcquisitionPerformanceEventPort() -> any AcquisitionPerformanceEventPort {
        #if ACQUISITION_PERFORMANCE_MEASUREMENT
        return OSSignpostAcquisitionPerformanceAdapter.makeIfValid(
            runIdentifier: ProcessInfo.processInfo.environment["PROJECTZD8_ACQUISITION_PERFORMANCE_RUN_ID"]
        ) ?? NoOpAcquisitionPerformanceEventPort()
        #else
        return NoOpAcquisitionPerformanceEventPort()
        #endif
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
            role: .iPhone,
            accountDeletionCheck: AccountDeletionMarkerComposition.check
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
    /// - Parameter database: アカウント削除時に消去する車両別対応PIDの保存先が共有する製品DB接続。
    /// - Parameter connectionSessionStorage: アカウント削除時に接続履歴とRawログを消去する共通保存先。
    /// - Returns: 実Appleアカウント認証を使用する認証セッションモデル。
    static func makeAuthenticationSessionModel(
        database: ApplicationDatabaseConnection,
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
        let vehiclePIDCapabilityEraser = makeVehiclePIDCapabilityRepository(database: database)
        let dataEraser = ProjectZD8AccountDataEraser(
            accountSettingsStore: accountSettingsStore,
            defaultAdapterStore: defaultAdapterStore,
            connectionSessionStorage: connectionSessionStorage,
            vehicleDataEraser: vehicleDataEraser,
            vehiclePIDCapabilityEraser: vehiclePIDCapabilityEraser,
            maintenanceRecordRepository: ProductDatabaseRepositoryFactory().makeMaintenanceRecordRepository(database: database)
        )
        let model = AuthenticationSessionModel(
            state: initialAuthenticationState,
            restoreSession: RestoreAuthenticationSessionUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore
            ),
            signInWithApple: SignInWithAppleUseCase(
                authorizationPort: authorization,
                sessionStore: sessionStore,
                deletionMarker: AccountDeletionMarkerComposition.marker
            ),
            deleteAccount: DeleteAccountUseCase(
                sessionRevocation: sessionRevocation,
                sessionTransfers: CloudKitConnectionSessionTransferRepository(),
                vehicleDataEraser: vehicleDataEraser,
                maintenanceDataEraser: CloudKitMaintenanceRemoteStore(),
                dataEraser: dataEraser,
                sessionStore: sessionStore,
                deletionMarker: AccountDeletionMarkerComposition.marker,
                vehicleIDStore: UserDefaultsAccountDeletionVehicleIDStore()
            ),
            remoteAccountLogout: RemoteAccountLogoutUseCase(
                dataEraser: dataEraser,
                sessionStore: sessionStore
            ),
            sessionRevocation: sessionRevocation,
            deletionFailureClassifier: CloudKitAccountDeletionFailureClassifier()
        )
        AccountDeletionMarkerComposition.gate.onAccountDeleted = { [weak model] accountIdentifier in
            model?.applyRemoteSessionRevocation(for: accountIdentifier)
        }
        return model
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

    /// 端末ローカルの自動記録設定と選択画面の表示済みフラグを注入したモデルを生成します。
    ///
    /// 責務: iOSの `UserDefaults` 保存実装を自動記録設定と記録開始方法の選択画面の状態へ結び付けます。
    /// - Returns: 保存済みの値を読み込んだ自動記録設定モデル。
    static func makeAutomaticRecordingPreferenceModel() -> AutomaticRecordingPreferenceModel {
        AutomaticRecordingPreferenceModel(
            preference: AutomaticRecordingPreferenceUseCase(
                preferencePort: UserDefaultsAutomaticRecordingPreferenceStore()
            ),
            promptCompletion: AutomaticRecordingChoicePromptCompletionUseCase(
                completionPort: UserDefaultsAutomaticRecordingChoicePromptCompletionStore()
            )
        )
    }

    /// 接続履歴の保存先を注入した未登録車両の警告モデルを生成します。
    ///
    /// 責務: 観測VIN付きセッションの照会境界を未登録車両の警告へ結び付けます。
    /// - Parameter repository: 車両未割当かつ観測VINを持つセッションを照会する保存先。
    /// - Returns: 未サインインの非表示状態から始まる警告モデル。
    static func makeUnassignedObservedVINWarningModel(
        repository: any ObservedVINConnectionSessionRepository
    ) -> UnassignedObservedVINWarningModel {
        UnassignedObservedVINWarningModel(
            loadSessions: LoadUnassignedObservedVINConnectionSessionsUseCase(repository: repository)
        )
    }

    /// 接続履歴の保存先を注入した、車両を特定できなかったログの警告と紐付けのモデルを生成します。
    ///
    /// 責務: 車両不明ログの照会と紐付けを保存先へ結び付け、紐付け後の履歴の再読込を既存の観測VINの紐付けと同じ通知へ結び付けます。
    /// - Parameters:
    ///   - repository: 車両不明ログの照会と紐付けを行う保存先。
    ///   - historyDidChange: 1件以上紐付けた後に履歴を読み込み直させる処理。
    /// - Returns: 未サインインの非表示状態から始まるモデル。
    static func makeVehicleUnknownSessionModel(
        repository: any VehicleUnknownConnectionSessionRepository,
        historyDidChange: @escaping @MainActor () -> Void
    ) -> VehicleUnknownSessionModel {
        VehicleUnknownSessionModel(
            loadSessions: LoadVehicleUnknownConnectionSessionsUseCase(repository: repository),
            assignVehicle: AssignVehicleToVehicleUnknownConnectionSessionsUseCase(
                repository: repository,
                historyDidChange: historyDidChange
            )
        )
    }

    /// 選択済みiOS Bluetooth終端に対応するELM/STNバイトストリームを生成します。
    ///
    /// 責務: 1件のBLEまたはBluetooth Classic終端を対応するOBDコマンドTransportへ変換します。
    /// BLE終端は、常駐リンクが同じアダプターを `ready` で保持していれば常駐リンク上のTransportを、そうでなければ自前のTransportを使います。
    /// ただしPID取得では、常駐リンクで始めた記録の間は常駐リンクだけを使い、`ready` でなければ自前の接続を開かずに失敗します。
    /// - Parameters:
    ///   - endpoint: 選択済みアダプターの物理終端。
    ///   - configuration: Bluetooth Classic用にInfo.plistから読み取ったExternalAccessoryプロトコル許可集合。
    ///   - residentLink: 常駐リンク一式。
    ///   - isTelemetry: PID取得(回復操作を含む)のTransportなら `true`、車両識別なら `false`。
    /// - Returns: 選択済み終端のELM/STN連続バイト通信に使用するTransport。
    /// - Throws: 未構成、対象外Transport、UUID不正、または通信生成条件を満たさない場合の識別エラー。
    ///   常駐リンクで始めた記録の取得で常駐リンクが `ready` でない場合は `OBDPIDTelemetryError.connectionLost`。
    private static func makeBluetoothOBDTransport(
        for endpoint: OBDConnectionEndpoint,
        configuration: IOSExternalAccessoryProtocolConfiguration,
        residentLink: IOSResidentAdapterLink,
        isTelemetry: Bool
    ) throws -> any OBDCommandTransport {
        switch endpoint.transport {
        case .bluetoothLowEnergy:
            let makeOwnTransport: (OBDConnectionEndpoint) throws -> any OBDCommandTransport = {
                try AppleCoreBluetoothOBDTransport(endpoint: $0)
            }
            guard isTelemetry else {
                return try residentLink.transportSelector.transport(for: endpoint, fallback: makeOwnTransport)
            }
            return try residentLink.transportSelector.telemetryTransport(for: endpoint, fallback: makeOwnTransport)
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
