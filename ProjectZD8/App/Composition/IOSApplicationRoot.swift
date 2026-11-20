#if os(iOS)
import Foundation

/// iOSアプリのルートが保持する、共通のモデル一式とiOS固有のモデル・常駐リンク監視です。
///
/// 保存先と接続セッション系のモデルは `ApplicationRootAssembly.makeFoundation` の土台を使い、
/// PID継続取得と車両管理のモデルだけを、常駐リンクと記録の調停役を通す配線で結び付けます。
@MainActor
struct IOSApplicationRoot {
    /// iOSとmacOSで共通のモデル一式です。
    let models: ApplicationRootModels
    /// 自動記録設定と記録開始方法の選択画面の状態を保持するモデルです。
    let automaticRecording: AutomaticRecordingPreferenceModel
    /// 未登録車両の警告を保持するモデルです。
    let unassignedVINWarning: UnassignedObservedVINWarningModel
    /// 車両を特定できなかったログの警告と紐付けを保持するモデルです。
    let vehicleUnknownSessions: VehicleUnknownSessionModel
    /// アプリ側の事実を常駐リンク監視へ伝える型です。
    let adapterLinkSupervision: IOSAdapterLinkSupervisionDriver
    /// PID継続取得の状態と前面復帰を記録中の常時表示(Live Activity)へ伝える型です。
    let sessionActivity: IOSRecordingSessionActivityDriver
    /// 設定画面の「走行ルートを記録」区画のモデルです。
    let routeRecordingSettings: RouteRecordingSettingsModel

    /// iOSのルートモデル一式を組み立てます。
    ///
    /// 責務: 共通の土台・常駐リンク・記録の調停役・各Featureのモデルを生成し、通知応答の受け口と
    /// Live Activityの[切断]操作の受け口と、セッション終了後の後処理(`BGProcessingTask`)の予約・起動を有効にします。
    /// - Returns: 常駐リンク監視・常時表示・走行ルート記録の観測が未開始のルートモデル一式。
    ///   `adapterLinkSupervision.launch()`、`sessionActivity.launch()`、`models.sessionLocationRecording.launch()` で開始します。
    /// - Side Effects: 通知センターの delegate を車両検知通知へ置き換えます(起動完了前に呼ぶこと)。
    ///   [切断]操作の停止処理を `RecordingSessionStopIntentHandlerRegistry` へ登録します。
    ///   後処理の起動ハンドラを `BGTaskScheduler` へ登録します(起動完了前に呼ぶこと)。
    static func make() -> IOSApplicationRoot {
        let postSessionProcessing = IOSPostSessionProcessingComposition()
        let foundation = ApplicationRootAssembly.makeFoundation(
            IOSApplicationComposition.self,
            sessionEndPersisted: { postSessionProcessing.sessionEndPersisted($0) }
        )
        let authentication = IOSApplicationComposition.makeAuthenticationSessionModel(
            database: foundation.database,
            connectionSessionStorage: foundation.storage.sessions
        )
        let coordinator = IOSAdapterLinkComposition.makeRecordingCoordinator(
            lifecycle: foundation.lifecycle,
            authentication: authentication
        )
        let liveTelemetry = makeLiveTelemetryModel(foundation: foundation, coordinator: coordinator)
        let vehicleManagement = makeVehicleManagementModel(foundation: foundation, coordinator: coordinator)
        ConnectionSessionActivityRelay.start(lifecycle: foundation.lifecycle, vehicleManagement: vehicleManagement)
        registerSessionActivityStop(liveTelemetry: liveTelemetry)
        postSessionProcessing.registerLaunchHandler(
            foundation: foundation,
            liveTelemetry: liveTelemetry,
            authentication: authentication
        )
        let models = ApplicationRootModels(
            authentication: authentication,
            accountSettings: IOSApplicationComposition.makeAccountSettingsModel(),
            vehicleManagement: vehicleManagement,
            maintenance: IOSApplicationComposition.makeMaintenanceModel(database: foundation.database),
            liveTelemetry: liveTelemetry,
            connectionSessionLifecycle: foundation.lifecycle,
            connectionHistory: foundation.history,
            sessionLogAnalysis: foundation.analysis,
            sessionLocationRecording: foundation.sessionLocationRecording
        )
        return IOSApplicationRoot(
            models: models,
            automaticRecording: IOSApplicationComposition.makeAutomaticRecordingPreferenceModel(),
            unassignedVINWarning: IOSApplicationComposition.makeUnassignedObservedVINWarningModel(
                repository: foundation.storage.sessions
            ),
            vehicleUnknownSessions: IOSApplicationComposition.makeVehicleUnknownSessionModel(
                repository: foundation.storage.sessions,
                historyDidChange: { [history = foundation.history] in history.send(.localDataChanged) }
            ),
            adapterLinkSupervision: makeSupervisionDriver(
                coordinator: coordinator,
                authentication: authentication,
                lifecycle: foundation.lifecycle
            ),
            sessionActivity: IOSRecordingSessionActivityDriver.make(
                liveTelemetry: liveTelemetry,
                vehicleManagement: vehicleManagement
            ),
            routeRecordingSettings: foundation.routeRecordingSettings
        )
    }

    /// Live Activityの[切断]操作を、手動切断と同じ取得停止の要求へ結び付けます。
    ///
    /// 責務: 記録中だけ `LiveTelemetryAction.stopRequested` を送る停止処理を、Intentの登録先へ登録します。
    /// - Parameter liveTelemetry: 停止を要求するPID継続取得のモデル。
    private static func registerSessionActivityStop(liveTelemetry: LiveTelemetryModel) {
        let stop = StopRecordingFromSessionActivityUseCase(
            telemetryState: { liveTelemetry.state },
            requestStop: { liveTelemetry.send(.stopRequested) },
            lifecycleDiagnostics: OSLogRecordingSessionActivityLifecycleDiagnosticsAdapter()
        )
        RecordingSessionStopIntentHandlerRegistry.register { stop.execute() }
    }

    /// 通知応答を有効にした常駐リンク監視と、アプリ側の事実をそこへ伝える型を生成します。
    ///
    /// 責務: 車両検知通知の応答処理を有効にし、常駐リンク監視を認証状態と接続セッションのアカウントへ結び付けます。
    /// - Parameters:
    ///   - coordinator: 記録の開始・停止を受け取る調停役。
    ///   - authentication: 認証状態の持ち主。
    ///   - lifecycle: サインイン中アカウントの識別子を受け取る接続セッションのモデル。
    /// - Returns: 未開始の常駐リンク監視を持つ型。
    private static func makeSupervisionDriver(
        coordinator: VehicleRecordingCoordinator,
        authentication: AuthenticationSessionModel,
        lifecycle: ConnectionSessionLifecycleModel
    ) -> IOSAdapterLinkSupervisionDriver {
        let notifier = IOSVehicleDetectionNotifier()
        notifier.activateResponseHandling()
        let supervision = IOSAdapterLinkComposition.makeSupervision(
            residentLink: IOSApplicationComposition.residentLink,
            notifier: notifier,
            recordingControl: coordinator
        )
        return IOSAdapterLinkSupervisionDriver(
            supervision: supervision,
            authentication: authentication,
            accountIdentifierDidChange: { lifecycle.send(.accountIdentifierChanged($0)) }
        )
    }

    /// 記録の調停役へ結び付けたPID継続取得のモデルを生成します。
    ///
    /// 責務: 取得の終了を接続セッションの終了と調停役へ伝え、調停役の取得開始・停止をこのモデルへ結び付けます。
    /// - Parameters:
    ///   - foundation: 共通の土台。
    ///   - coordinator: 記録の調停役。
    /// - Returns: 手動接続と常駐リンクの両方から取得を始められるモデル。
    private static func makeLiveTelemetryModel(
        foundation: ApplicationRootFoundation,
        coordinator: VehicleRecordingCoordinator
    ) -> LiveTelemetryModel {
        let lifecycle = foundation.lifecycle
        let model = IOSApplicationComposition.makeLiveTelemetryModel(
            database: foundation.database,
            connectionSessionStorage: foundation.storage,
            activeSessionID: { await lifecycle.activeSession?.id },
            performanceEvents: foundation.performanceEvents,
            sessionDidEnd: { reason, endedAt in
                lifecycle.send(.endRequested(reason, endedAt: endedAt))
                coordinator.telemetryDidEnd(reason: reason)
            },
            distanceDidChange: { lifecycle.send(.distanceObserved($0)) }
        )
        IOSAdapterLinkComposition.connectTelemetry(
            of: coordinator,
            to: model,
            residentLink: IOSApplicationComposition.residentLink
        )
        return model
    }

    /// 手動接続の記録開始と登録後の紐付けを結び付けた車両管理のモデルを生成します。
    ///
    /// 責務: 手動接続の車両識別の開始・終了と識別結果(登録済み・未登録)を調停役へ、接続中に登録した車両を現在セッションへ、
    /// 新規登録を観測VINセッションの紐付け(記録中の現在セッション、続けて保存済みセッション)へ結び付けます。
    /// - Parameters:
    ///   - foundation: 共通の土台。
    ///   - coordinator: 記録の調停役。
    /// - Returns: 車両管理のモデル。
    private static func makeVehicleManagementModel(
        foundation: ApplicationRootFoundation,
        coordinator: VehicleRecordingCoordinator
    ) -> VehicleManagementModel {
        let history = foundation.history
        let lifecycle = foundation.lifecycle
        let assignSessions = AssignVehicleToObservedVINConnectionSessionsUseCase(
            repository: foundation.storage.sessions,
            historyDidChange: { history.send(.localDataChanged) }
        )
        return IOSApplicationComposition.makeVehicleManagementModel(
            database: foundation.database,
            connectionSessionRepository: foundation.storage.sessions,
            vehicleSessionsDidDelete: { history.send(.refreshRequested) },
            connectionVehicleDidResolve: { vehicle, endpoint, identification in
                coordinator.startManualRecording(
                    .manualConnection(vehicle: vehicle, endpoint: endpoint, identification: identification)
                )
            },
            unregisteredConnectionDidStart: { endpoint, identification in
                coordinator.startManualRecording(
                    .manualUnregisteredConnection(endpoint: endpoint, identification: identification)
                )
            },
            unregisteredConnectionVehicleDidRegister: { lifecycle.send(.unregisteredVehicleRegistered($0)) },
            vehicleDidRegister: { vehicle, accountIdentifier in
                lifecycle.send(.observedVINVehicleRegistered(vehicle))
                _ = try assignSessions.execute(vehicle: vehicle, accountIdentifier: accountIdentifier)
            },
            connectionIdentificationWillBegin: { coordinator.manualConnectionIdentificationWillBegin() },
            connectionIdentificationDidEnd: { coordinator.manualConnectionIdentificationDidEnd() }
        )
    }
}
#endif
