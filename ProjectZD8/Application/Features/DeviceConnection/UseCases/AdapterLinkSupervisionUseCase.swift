import Foundation

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

    /// 記録の開始・停止とリンク可用性の変化を伝える境界です。
    private let recordingControl: any AdapterLinkRecordingControlPort

    /// 現在時刻の取得元です。
    private let clock: any AdapterLinkSupervisionClock

    /// 非同期の作用を世代管理付きで実行する型です。
    private let operations: AdapterLinkSupervisionOperationRunner

    /// 状態・イベント・条件から次の状態と作用を決める純粋な遷移です。
    private let transition: AdapterLinkSupervisionTransition

    /// 検知待ち以外で届いた[記録開始]を有効期限つきの意思として保持する型です。
    private let recordingIntents: AdapterLinkRecordingIntentTracker

    /// いま記録中の記録が自動記録で始まり、開始の確定で「記録を開始しました」を出すべきかどうかです。
    private var announcesRecordingStart = false

    /// 記録中のリンク状態の変化から、記録側へ伝える可用性の変化を決める方針です。
    private let recordingLinkAvailability = AdapterLinkRecordingLinkAvailabilityPolicy()

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

    /// アプリが前面にいるかどうかです。最後の前面復帰の後に背面へ移っていなければ `true` です。
    private var isForeground = false

    /// 最後に車両確認(見張りの確認を含む)を送った時刻です(時計は単調時計基準)。続けて送っていなければ `nil` です。
    private var lastVehicleConfirmationSentAt: Date?

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
        recordingIntents = AdapterLinkRecordingIntentTracker(clock: clock, notifications: notifications)
        linkState = link.state
        operations.eventDidOccur = { [weak self] event in self?.send(event) }
        link.stateDidChange = { [weak self] linkState in self?.send(.linkStateChanged(linkState)) }
    }

    /// 監視を開始します。アプリ起動時(バックグラウンド起動を含む)に呼びます。
    ///
    /// 責務: 前のプロセスが残した監視通知を取り下げ(その通知からは記録を始められないため)、既定アダプター設定を読み込み、
    /// 稼働条件を満たせば常駐リンクを開始します。重複して呼んでもリンクは二重に開始しません。
    func start() {
        notifications.dismiss()
        isSupervisionStarted = true
        currentDefaultAdapterPreference = defaultAdapterPreference.load()
        send(.operatingConditionsChanged)
    }

    /// 監視を停止します。
    ///
    /// 責務: 常駐リンクを停止し、通知を取り下げ、記録中なら監視の停止(終了理由は接続断)として停止を要求します。
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
    /// 責務: 前面にいることを稼働条件へ反映し、リンクが `ready` の待機・窓切れの車両確認・抑止中の見張りを再開します。
    func appDidBecomeActive() {
        isForeground = true
        send(.appDidBecomeActive)
    }

    /// アプリが背面へ移ったことを反映します。
    ///
    /// 責務: 前面ではないことを稼働条件へ反映します。状態は変えません。背面でも車両確認は窓後の間隔(既定5秒)で続きます。
    func appDidEnterBackground() {
        isForeground = false
    }

    /// ユーザーが通知の[記録開始]を選んだことを反映します。
    ///
    /// 責務: 検知待ちなら記録開始を要求します。待機・初期化中・確認中・VIN読取中なら有効期限つきの意思として保持し
    /// (処理できない条件なら捨てて理由を通知し)、記録中・終了処理中・抑止中は無視します。
    func recordingStartSelected() {
        switch recordingIntents.policy.disposition(for: state, conditions: currentConditions()) {
        case .forwardToTransition:
            send(.recordingStartSelected)
        case .keepAsIntent:
            recordingIntents.keep()
        case let .reject(reason):
            recordingIntents.rejectSelection(reason)
        }
    }

    /// 記録側から記録開始の確定(接続セッションが作成され取得が始まった)を受け取ります。
    ///
    /// 責務: 自動記録で始めた記録なら「記録を開始しました」を出させます。記録中以外に届いた確定は遷移が無視します。
    func recordingDidStart() {
        let announces = announcesRecordingStart
        announcesRecordingStart = false
        send(.recordingStartConfirmed(announcesStart: announces))
    }

    /// 記録側から記録の終了を受け取ります。
    ///
    /// 責務: 記録中・終了中であれば終了を経て待機へ戻します。終了理由は監視の遷移へ渡します。
    /// 記録中から終わった記録(終了理由あり)なら、終了の処理の後に `recordingEndSettled` を続けて入力し、
    /// リンクが `ready` の待機なら検知をやり直し、ユーザー切断後の抑止なら見張りを始めさせます。
    /// 記録が始まらなかった・辞退した(終了理由なし)場合は、リンクが `ready` なら遷移が予約する窓後の間隔の待ちの後に
    /// 再初期化からやり直します(待ちを挟まずには再開しません)。監視が停止を要求した記録(終了中から終わる)はやり直しません。
    /// - Parameter endReason: 記録中から終わった時のテレメトリ終了理由。記録が始まらなかった・辞退した・手動記録に置き換えた場合は `nil`。
    func recordingDidFinish(endReason: ConnectionSessionEndReason?) {
        let finishedWhileRecording: Bool = if case .recording = state { true } else { false }
        announcesRecordingStart = false
        send(.recordingDidFinish(endReason: endReason))
        if finishedWhileRecording, endReason != nil {
            send(.recordingEndSettled)
        }
    }

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い始めたことを反映します。
    ///
    /// 責務: 使い終えるまで初期化・車両確認を抑止し、進行中の確認・検知と予約中の初期化再試行を取り消します。
    /// 記録中なら置き換えとして停止を要求します。リンクは止めません。
    func externalAdapterUseDidBegin() {
        isExternalAdapterUseActive = true
        operations.cancelInitializationRetry()
        send(.externalAdapterUseBegan)
    }

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い終えたことを反映します。
    ///
    /// 責務: 抑止を解きます。待機でリンクが `ready` なら、すぐ初期化からやり直します。
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
    /// 責務: 現在の条件を組み立てて遷移結果を得て、状態の更新・変化通知・作用の実行を順に行い、
    /// 記録中のリンク可用性の変化があれば最後に記録側へ伝えます。
    /// - Parameter event: 処理するイベント。
    private func process(_ event: AdapterLinkSupervisionEvent) {
        let conditions = currentConditions()
        let previous = state
        let result = transition.result(from: state, on: event, conditions: conditions)
        let availabilityChange = recordingLinkAvailability.availabilityChange(on: event, from: state, conditions: conditions)
        if case let .linkStateChanged(newLinkState) = event {
            linkState = newLinkState
        }
        if result.state != state {
            state = result.state
            stateDidChange?(state)
        }
        result.effects.forEach(execute)
        if let availabilityChange {
            recordingControl.recordingLinkAvailabilityDidChange(isAvailable: availabilityChange)
        }
        updateRecordingIntent(after: event, from: previous, conditions: conditions)
    }

    /// 1件のイベントの処理後に、記録開始の意思と開始通知の要否を更新します。
    ///
    /// 責務: VIN読取の完了で意思を使い終え(期限切れでも通知せずに消し)、自動記録で記録中へ移ったかを覚えます。
    /// 稼働条件の変化で意思を処理できなくなったら、意思を捨てて理由を通知します。
    /// - Parameters:
    ///   - event: 処理したイベント。
    ///   - previous: 処理前の監視状態。
    ///   - conditions: 処理時の条件。
    private func updateRecordingIntent(
        after event: AdapterLinkSupervisionEvent,
        from previous: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) {
        switch event {
        case let .vinReadCompleted(_, isAutomaticRecordingEnabled), let .vinReadFailed(isAutomaticRecordingEnabled):
            guard case .vehicleDetected(_, .readingVIN) = previous else { return }
            let isRecording: Bool = if case .recording = state { true } else { false }
            announcesRecordingStart = isRecording && isAutomaticRecordingEnabled
            recordingIntents.detectionDidComplete()
        case .operatingConditionsChanged:
            if let reason = recordingIntents.policy.rejectionReason(conditions) {
                recordingIntents.discard(reason)
            }
        default:
            return
        }
    }

    /// 遷移へ渡す現在の条件を返します。
    ///
    /// 責務: 稼働条件・リンクの接続対象・直前のリンク状態・現在時刻・前面かどうか・最後に確認を送った時刻を1件の条件値へまとめます。
    /// - Returns: 現在の条件。
    private func currentConditions() -> AdapterLinkSupervisionConditions {
        AdapterLinkSupervisionConditions(
            isSupervisionStarted: isSupervisionStarted,
            isSignedIn: isSignedIn,
            defaultAdapterPreference: currentDefaultAdapterPreference,
            linkPreference: linkPreference,
            linkState: linkState,
            now: clock.now,
            isExternalAdapterUseActive: isExternalAdapterUseActive,
            isForeground: isForeground,
            lastVehicleConfirmationSentAt: lastVehicleConfirmationSentAt,
            hasValidRecordingIntent: recordingIntents.hasValidIntent
        )
    }

    /// 1件の作用を実行します。
    ///
    /// 責務: 作用をリンク操作として直接実行するか、非同期処理系・通知と記録系の実行へ振り分けます。判断は行いません。
    /// - Parameter effect: 実行する作用。
    private func execute(_ effect: AdapterLinkSupervisionEffect) {
        switch effect {
        case let .startLink(preference):
            linkPreference = preference
            link.start(preference: preference)
        case .stopLink:
            linkPreference = nil
            operations.cancelInitializationRetry()
            link.stop()
        case .prepareNotifications:
            prepareNotificationsIfNeeded()
        case .cancelOperations, .initializeAdapter, .confirmVehicle, .scheduleVehicleConfirmation,
             .scheduleAdapterInitializationRetry, .readVIN:
            executeOperationEffect(effect)
        case .presentVehicleDetected, .presentRecordingStarted, .dismissNotification, .requestRecordingStart,
             .requestRecordingStop, .completeFinishing:
            executeNotificationOrRecordingEffect(effect)
        }
    }

    /// 非同期処理系(初期化・車両確認・予約・VIN読取・取り消し)の作用を実行します。
    ///
    /// 責務: 作用を `AdapterLinkSupervisionOperationRunner` の呼び出しへ変換し、最後に確認を送った時刻を更新します。
    /// - Parameter effect: 実行する作用。他の系統の作用は無視します。
    private func executeOperationEffect(_ effect: AdapterLinkSupervisionEffect) {
        switch effect {
        case .cancelOperations:
            lastVehicleConfirmationSentAt = nil
            operations.cancel()
        case .initializeAdapter:
            lastVehicleConfirmationSentAt = nil
            operations.initializeAdapter()
        case let .confirmVehicle(timeout):
            lastVehicleConfirmationSentAt = clock.now
            operations.confirmVehicle(timeout: timeout)
        case let .scheduleVehicleConfirmation(duration):
            operations.scheduleVehicleConfirmation(after: duration)
        case let .scheduleAdapterInitializationRetry(duration):
            operations.scheduleInitializationRetry(after: duration)
        case .readVIN:
            lastVehicleConfirmationSentAt = nil
            operations.readVIN()
        default:
            break
        }
    }

    /// 通知と記録の作用を実行します。
    ///
    /// 責務: 作用を通知・記録制御の呼び出しか、終了処理の完了イベントの入力へ変換します。
    /// - Parameter effect: 実行する作用。他の系統の作用は無視します。
    private func executeNotificationOrRecordingEffect(_ effect: AdapterLinkSupervisionEffect) {
        switch effect {
        case let .presentVehicleDetected(vin):
            notifications.presentVehicleDetected(vin: vin)
        case let .presentRecordingStarted(vin):
            notifications.presentRecordingStarted(vin: vin)
        case .dismissNotification:
            notifications.dismiss()
        case let .requestRecordingStart(request):
            recordingControl.requestRecordingStart(request)
        case let .requestRecordingStop(reason):
            recordingControl.requestRecordingStop(reason: reason)
        case .completeFinishing:
            send(.finishingDidComplete)
        default:
            break
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
