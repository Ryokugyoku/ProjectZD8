/// 常駐BLEリンクの状態と車両の応答から、車両検知・通知または自動記録開始・記録終了までを監視します。
///
/// 分岐は `AdapterLinkSupervisionTransition` が決め、このユースケースは入力をイベントへ変換して遷移結果の作用を実行するだけです。
/// 生成時に `AdapterLinkPort.stateDidChange` を自身へ結び付けます。
@MainActor
final class AdapterLinkSupervisionUseCase {
    /// 1回の入力から連鎖して処理するイベント数の上限です。作用の連鎖が止まらない不具合を検出するための上限です。
    private static let maximumEventsPerInput = 64

    /// 現在の監視状態です。
    private(set) var state: AdapterLinkSupervisionState = .standby

    /// 通知の提示が許可されたかどうかです。準備が完了していない場合は `nil` です。
    private(set) var isNotificationAuthorized: Bool?

    /// 監視状態が変化したときに新しい状態を受け取る処理です。
    var stateDidChange: (@MainActor (AdapterLinkSupervisionState) -> Void)?

    /// 常駐リンクの能力です。
    private let link: any AdapterLinkPort

    /// 保存済み既定アダプターの読込元です。
    private let defaultAdapterPreference: DefaultAdapterPreferenceUseCase

    /// 車両検知通知の能力です。
    private let notifications: any VehicleDetectionNotificationPort

    /// 記録の開始・停止を依頼する境界です。
    private let recordingControl: any AdapterLinkRecordingControlPort

    /// 現在時刻の取得元です。
    private let clock: any AdapterLinkSupervisionClock

    /// 非同期の作用を世代管理付きで実行する型です。
    private let operations: AdapterLinkSupervisionOperationRunner

    /// 状態・イベント・条件から次の状態と作用を決める純粋な遷移です。
    private let transition: AdapterLinkSupervisionTransition

    /// `start()` 済みで `stop()` されていないかどうかです。
    private var isSupervisionStarted = false

    /// ユーザーがサインイン済みかどうかです。
    private var isSignedIn = false

    /// 最後に読み込んだ既定アダプター設定です。
    private var currentDefaultAdapterPreference: DefaultAdapterPreference?

    /// 常駐リンクを開始したときの接続対象設定です。リンクを開始していない場合は `nil` です。
    private var linkPreference: DefaultAdapterPreference?

    /// 最後に処理したリンク状態です。
    private var linkState: AdapterLinkState

    /// 常駐リンク以外の経路(手動接続)がアダプターを使っている最中かどうかです。
    private var isExternalAdapterUseActive = false

    /// 通知の準備を一度でも始めたかどうかです。
    private var hasStartedNotificationPreparation = false

    /// 処理待ちのイベントです。作用の実行中に届いた入力はここへ積んで順に処理します。
    private var pendingEvents: [AdapterLinkSupervisionEvent] = []

    /// イベントを処理中かどうかです。
    private var isProcessingEvents = false

    /// 監視に必要な能力を注入して生成します。
    ///
    /// 責務: 常駐リンク・初期化・車両確認・VIN読取・通知・自動記録設定・記録制御・時刻の依存関係を固定し、リンク状態の受け口を結び付けます。
    /// - Parameters:
    ///   - link: 常駐リンクの能力。
    ///   - defaultAdapterPreference: 保存済み既定アダプターの読込元。
    ///   - initialization: アダプター初期化の能力。
    ///   - vehicleResponse: 車両確認の能力。
    ///   - vinReader: VIN読取の能力。
    ///   - notifications: 車両検知通知の能力。
    ///   - automaticRecordingPreference: 自動記録設定の保存境界。
    ///   - recordingControl: 記録の開始・停止を依頼する境界。
    ///   - clock: 現在時刻と待機の能力。
    ///   - timing: 確認窓と再確認間隔。既定は本番用の定数。
    init(
        link: any AdapterLinkPort,
        defaultAdapterPreference: DefaultAdapterPreferenceUseCase,
        initialization: any AdapterLinkInitializationPort,
        vehicleResponse: any VehicleResponseConfirmationPort,
        vinReader: any VehicleIdentificationNumberReadingPort,
        notifications: any VehicleDetectionNotificationPort,
        automaticRecordingPreference: any AutomaticRecordingPreferencePort,
        recordingControl: any AdapterLinkRecordingControlPort,
        clock: any AdapterLinkSupervisionClock,
        timing: AdapterLinkSupervisionTiming = .standard
    ) {
        self.link = link
        self.defaultAdapterPreference = defaultAdapterPreference
        self.notifications = notifications
        self.recordingControl = recordingControl
        self.clock = clock
        operations = AdapterLinkSupervisionOperationRunner(
            initialization: initialization,
            vehicleResponse: vehicleResponse,
            vinReader: vinReader,
            automaticRecordingPreference: automaticRecordingPreference,
            clock: clock
        )
        transition = AdapterLinkSupervisionTransition(timing: timing)
        linkState = link.state
        operations.eventDidOccur = { [weak self] event in self?.send(event) }
        link.stateDidChange = { [weak self] linkState in self?.send(.linkStateChanged(linkState)) }
    }

    /// 監視を開始します。アプリ起動時(バックグラウンド起動を含む)に呼びます。
    ///
    /// 責務: 既定アダプター設定を読み込み、稼働条件を満たせば常駐リンクを開始します。重複して呼んでもリンクは二重に開始しません。
    func start() {
        isSupervisionStarted = true
        currentDefaultAdapterPreference = defaultAdapterPreference.load()
        send(.operatingConditionsChanged)
    }

    /// 監視を停止します。
    ///
    /// 責務: 常駐リンクを停止し、通知を取り下げ、記録中なら停止を要求します。
    func stop() {
        isSupervisionStarted = false
        send(.operatingConditionsChanged)
    }

    /// 認証状態の変化を反映します。
    ///
    /// 責務: サインイン済みかどうかを稼働条件へ反映し、サインアウトでは監視を巻き戻します。
    /// - Parameter isSignedIn: サインイン済みなら `true`。
    func authenticationDidChange(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
        send(.operatingConditionsChanged)
    }

    /// 既定アダプター設定の変化を反映します。
    ///
    /// 責務: 既定アダプター設定を読み直し、削除・BLE以外への変更では停止、別のBLEアダプターへの変更では開始し直します。
    func defaultAdapterPreferenceDidChange() {
        currentDefaultAdapterPreference = defaultAdapterPreference.load()
        send(.operatingConditionsChanged)
    }

    /// アプリの前面復帰を反映します。
    ///
    /// 責務: リンクが `ready` の待機か休止中の車両確認であれば、確認を再開します。
    func appDidBecomeActive() {
        send(.appDidBecomeActive)
    }

    /// ユーザーが通知の[記録開始]を選んだことを反映します。
    ///
    /// 責務: 検知済みの時だけ記録開始を要求します。それ以外の状態では記録を始めません。
    func recordingStartSelected() {
        send(.recordingStartSelected)
    }

    /// 記録側から記録の終了を受け取ります。
    ///
    /// 責務: 記録中・終了中であれば終了を経て待機へ戻します。
    func recordingDidFinish() {
        send(.recordingDidFinish)
    }

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い始めたことを反映します。
    ///
    /// 責務: 使い終えるまで初期化・車両確認を抑止し、進行中の確認・検知を取り消します。記録中なら停止を要求します。リンクは止めません。
    func externalAdapterUseDidBegin() {
        isExternalAdapterUseActive = true
        send(.externalAdapterUseBegan)
    }

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い終えたことを反映します。
    ///
    /// 責務: 抑止を解きます。すぐには再確認せず、次の再接続か前面復帰で初期化からやり直します。
    func externalAdapterUseDidEnd() {
        isExternalAdapterUseActive = false
        send(.externalAdapterUseEnded)
    }

    /// 1件のイベントを処理待ちへ積み、処理中でなければ順に処理します。
    ///
    /// 責務: 作用の実行中に届いた入力を再入させず、上限件数まで届いた順に処理します。
    /// - Parameter event: 入力するイベント。
    private func send(_ event: AdapterLinkSupervisionEvent) {
        pendingEvents.append(event)
        guard !isProcessingEvents else { return }
        isProcessingEvents = true
        defer { isProcessingEvents = false }

        var processedCount = 0
        while !pendingEvents.isEmpty, processedCount < Self.maximumEventsPerInput {
            process(pendingEvents.removeFirst())
            processedCount += 1
        }
        if !pendingEvents.isEmpty {
            pendingEvents.removeAll()
            assertionFailure("AdapterLinkSupervisionUseCase: 1回の入力で連鎖するイベントが上限を超えました。")
        }
    }

    /// 1件のイベントを遷移へ渡し、結果の状態を反映して作用を実行します。
    ///
    /// 責務: 現在の条件を組み立てて遷移結果を得て、状態の更新・変化通知・作用の実行を順に行います。
    /// - Parameter event: 処理するイベント。
    private func process(_ event: AdapterLinkSupervisionEvent) {
        let result = transition.result(from: state, on: event, conditions: currentConditions())
        if case let .linkStateChanged(newLinkState) = event {
            linkState = newLinkState
        }
        if result.state != state {
            state = result.state
            stateDidChange?(state)
        }
        result.effects.forEach(execute)
    }

    /// 遷移へ渡す現在の条件を返します。
    ///
    /// 責務: 稼働条件・リンクの接続対象・直前のリンク状態・現在時刻を1件の条件値へまとめます。
    /// - Returns: 現在の条件。
    private func currentConditions() -> AdapterLinkSupervisionConditions {
        AdapterLinkSupervisionConditions(
            isSupervisionStarted: isSupervisionStarted,
            isSignedIn: isSignedIn,
            defaultAdapterPreference: currentDefaultAdapterPreference,
            linkPreference: linkPreference,
            linkState: linkState,
            now: clock.now,
            isExternalAdapterUseActive: isExternalAdapterUseActive
        )
    }

    /// 1件の作用を実行します。
    ///
    /// 責務: 作用を対応する能力の呼び出しへ変換します。判断は行いません。
    /// - Parameter effect: 実行する作用。
    private func execute(_ effect: AdapterLinkSupervisionEffect) {
        switch effect {
        case let .startLink(preference):
            linkPreference = preference
            link.start(preference: preference)
        case .stopLink:
            linkPreference = nil
            link.stop()
        case .prepareNotifications:
            prepareNotificationsIfNeeded()
        case .cancelOperations:
            operations.cancel()
        case .initializeAdapter:
            operations.initializeAdapter()
        case let .confirmVehicle(timeout):
            operations.confirmVehicle(timeout: timeout)
        case let .scheduleVehicleConfirmation(duration):
            operations.scheduleVehicleConfirmation(after: duration)
        case .readVIN:
            operations.readVIN()
        case let .presentVehicleDetected(vin):
            notifications.presentVehicleDetected(vin: vin)
        case let .presentRecordingStarted(vin):
            notifications.presentRecordingStarted(vin: vin)
        case .dismissNotification:
            notifications.dismiss()
        case let .requestRecordingStart(request):
            recordingControl.requestRecordingStart(request)
        case .requestRecordingStop:
            recordingControl.requestRecordingStop()
        case .completeFinishing:
            send(.finishingDidComplete)
        }
    }

    /// 通知の準備をユースケースの生存中に一度だけ始めます。
    ///
    /// 責務: 通知許可・カテゴリ登録・[記録開始]の受け口登録を依頼し、許可の結果を保持します。
    private func prepareNotificationsIfNeeded() {
        guard !hasStartedNotificationPreparation else { return }
        hasStartedNotificationPreparation = true
        Task { [weak self, notifications] in
            let isAuthorized = await notifications.prepare { [weak self] in
                self?.recordingStartSelected()
            }
            self?.isNotificationAuthorized = isAuthorized
        }
    }
}
