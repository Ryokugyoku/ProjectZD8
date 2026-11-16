/// 手動接続と常駐リンク監視の両方から記録を始め、常駐リンク監視へ記録の終了を必ず1回返す調停役です。
///
/// 常駐リンク監視の記録制御ポートを実装します。LiveTelemetry と常駐リンク監視の具象型には依存せず、
/// テレメトリの開始・停止と監視への終了通知は、生成後に App が設定するクロージャで行います。
@MainActor
final class VehicleRecordingCoordinator: AdapterLinkRecordingControlPort {
    /// 常駐リンク監視から依頼された記録の段階です。
    private(set) var phase: VehicleRecordingCoordinatorPhase = .idle

    /// 手動接続がアダプターを使っている段階です。
    private(set) var manualAdapterUse: VehicleRecordingManualAdapterUse = .idle

    /// 直近の登録済み車両の照合で発生したエラーです。照合に成功するたびに `nil` へ戻ります。
    ///
    /// 照合に失敗した場合も記録は車両なし(観測VINあり)で続けます。失敗はこの値と診断記録に残します。
    private(set) var lastVehicleLookupError: (any Error)?

    /// 直近に常駐リンク監視からの記録開始要求を断った理由です。開始へ進んだ要求が来るたびに `nil` へ戻ります。
    private(set) var lastStartDeclineReason: VehicleRecordingStartDeclineReason?

    /// 記録開始要求でテレメトリを開始する処理です。未設定の場合、常駐リンクからの記録は開始失敗になります。
    var startTelemetry: (@MainActor (VehicleRecordingStartRequest) -> Void)?

    /// 進行中のテレメトリを、保存すべき終了理由を付けて停止する処理です。停止後のテレメトリ終了は `telemetryDidEnd(reason:)` で受け取ります。
    ///
    /// ユーザーの[切断]とは別の経路です(引数がユーザー切断になることはありません)。
    var stopTelemetry: (@MainActor (ConnectionSessionEndReason) -> Void)?

    /// 常駐リンク監視から依頼された記録中に、リンクの可用性の変化をテレメトリへ伝える処理です。
    /// 引数はリンクが送受信できる状態へ戻ったら `true`、切れたら `false` です。
    var telemetryLinkAvailabilityDidChange: (@MainActor (Bool) -> Void)?

    /// 常駐リンク監視へ記録の終了を返す処理です(`AdapterLinkSupervisionUseCase.recordingDidFinish(endReason:)` を結び付けます)。
    /// 引数は記録中から終わった時のテレメトリ終了理由で、記録が始まらなかった・辞退した・手動記録に置き換えた場合は `nil` です。
    var supervisedRecordingDidFinish: (@MainActor (ConnectionSessionEndReason?) -> Void)?

    /// 常駐リンク監視から依頼された記録の開始が確定したことを監視へ伝える処理です(`AdapterLinkSupervisionUseCase.recordingDidStart()` を結び付けます)。
    var supervisedRecordingDidStart: (@MainActor () -> Void)?

    /// 手動接続がアダプターを使い始めたことを常駐リンク監視へ伝える処理です(`externalAdapterUseDidBegin()` を結び付けます)。
    var manualAdapterUseDidBegin: (@MainActor () -> Void)?

    /// 手動接続がアダプターを使い終えたことを常駐リンク監視へ伝える処理です(`externalAdapterUseDidEnd()` を結び付けます)。
    var manualAdapterUseDidEnd: (@MainActor () -> Void)?

    /// 接続セッション側の開始手順です。
    private let startSession: StartVehicleRecordingSessionUseCase

    /// VINに一致する登録済み車両を返す処理です。
    private let findVehicle: @MainActor (String?) async throws -> VehicleProfile?

    /// 照合中の依頼を識別する世代です。停止や置き換えで進め、古い照合結果を捨てます。
    private var lookupGeneration: UInt64 = 0

    /// 進行中の車両照合です。
    private var lookupTask: Task<Void, Never>?

    /// 開始拒否と照合失敗を診断記録へ残す境界です。`nil` なら出力しません(状態には残ります)。
    private let diagnostics: (any VehicleRecordingDiagnosticsPort)?

    /// 接続セッションの開始手順と車両照合を注入して生成します。
    ///
    /// 責務: 記録開始に使う依存関係を固定します。出力のクロージャは生成後に設定します。
    /// - Parameters:
    ///   - startSession: 接続セッション側の開始手順。
    ///   - findVehicle: VINに一致するサインイン中アカウントの登録済み車両を返す処理。
    ///   - diagnostics: 開始拒否と照合失敗の診断記録先。既定は出力なし。
    init(
        startSession: StartVehicleRecordingSessionUseCase,
        findVehicle: @escaping @MainActor (String?) async throws -> VehicleProfile?,
        diagnostics: (any VehicleRecordingDiagnosticsPort)? = nil
    ) {
        self.startSession = startSession
        self.findVehicle = findVehicle
        self.diagnostics = diagnostics
    }

    /// 手動接続の車両識別がアダプターへ接続し始めることを受け取ります。
    ///
    /// 責務: 手動接続がアダプターを使っていなければ、使い始めたことを常駐リンク監視へ1回伝えます。手動の記録中なら何もしません。
    func manualConnectionIdentificationWillBegin() {
        guard manualAdapterUse == .idle else { return }
        manualAdapterUse = .identifying
        manualAdapterUseDidBegin?()
    }

    /// 手動接続の車両識別が終わったことを受け取ります(成功・失敗・登録確認待ちのすべて)。
    ///
    /// 責務: 識別の直後に記録を始めなかった場合だけ、使い終えたことを常駐リンク監視へ1回伝えます。
    func manualConnectionIdentificationDidEnd() {
        guard manualAdapterUse == .identifying else { return }
        endManualAdapterUse()
    }

    /// 手動接続で識別した車両(登録済み、または未登録で車両なし)の記録を始めます。
    ///
    /// 責務: 常駐リンク監視から依頼された記録があれば終了扱いにし、手動のアダプター使用を記録中にしてから、
    /// セッションの有無に関係なくテレメトリを始めます。テレメトリを始められなければ使用を終えます。
    /// - Parameter request: 手動接続の記録開始要求。
    func startManualRecording(_ request: VehicleRecordingStartRequest) {
        endSupervisedRecordingForReplacement()
        if manualAdapterUse == .idle {
            manualAdapterUseDidBegin?()
        }
        manualAdapterUse = .recording
        if !begin(request, requirement: .optional) {
            endManualAdapterUse()
        }
    }

    /// 常駐リンク監視からの記録開始要求を受け取ります。
    ///
    /// 責務: 他の記録が進行中なら開始せず終了を返し、そうでなければVINで登録済み車両を照合してから記録を始めます。
    /// - Parameter request: 接続終端・読み取ったVIN・アダプター判定結果。
    func requestRecordingStart(_ request: AdapterLinkRecordingStartRequest) {
        guard phase == .idle else {
            declineRecordingStart(.coordinatorBusy(phase))
            return
        }
        guard !startSession.hasActiveSession else {
            declineRecordingStart(.anotherSessionActive)
            return
        }
        lastStartDeclineReason = nil
        phase = .resolvingVehicle
        lookupGeneration &+= 1
        let generation = lookupGeneration
        lookupTask = Task { [weak self, findVehicle] in
            let result: Result<VehicleProfile?, any Error>
            do {
                result = .success(try await findVehicle(request.vin))
            } catch {
                result = .failure(error)
            }
            self?.vehicleLookupDidFinish(result, for: request, generation: generation)
        }
    }

    /// 常駐リンク監視からの記録停止要求を受け取ります。
    ///
    /// 責務: 照合中なら照合を捨てて終了を返し、記録中なら停止理由の終了理由でテレメトリを停止して終了を待ちます。
    /// - Parameter reason: 停止の理由。保存する終了理由へ写してテレメトリへ渡します。
    func requestRecordingStop(reason: AdapterLinkRecordingStopReason) {
        switch phase {
        case .idle:
            return
        case .resolvingVehicle:
            cancelVehicleLookup()
            phase = .idle
            notifySupervisedRecordingFinished(endReason: nil)
        case .recording:
            guard let stopTelemetry else {
                phase = .idle
                notifySupervisedRecordingFinished(endReason: nil)
                return
            }
            stopTelemetry(reason.sessionEndReason)
        }
    }

    /// 常駐リンク監視から、記録中のリンク可用性の変化を受け取ります。
    ///
    /// 責務: 常駐リンク監視から依頼された記録中の時だけ、変化をテレメトリへ伝えます。手動接続の記録・照合中・待機中は何もしません。
    /// - Parameter isAvailable: リンクが送受信できる状態へ戻ったら `true`、切れたら `false`。
    func recordingLinkAvailabilityDidChange(isAvailable: Bool) {
        guard phase == .recording else { return }
        telemetryLinkAvailabilityDidChange?(isAvailable)
    }

    /// テレメトリの取得が始まった(取得対象が確定した)ことを受け取ります。
    ///
    /// 責務: 常駐リンク監視から依頼された記録中(接続セッションを作成してテレメトリを始めた後)の時だけ、開始の確定を監視へ伝えます。
    /// 手動接続の記録・照合中・待機中(既に終わった記録の古い通知を含む)は何もしません。
    func telemetryDidStart() {
        guard phase == .recording else { return }
        supervisedRecordingDidStart?()
    }

    /// テレメトリが終了したことを受け取ります(終了理由を問わず、テレメトリの終了通知ごとに呼びます)。
    ///
    /// 責務: 常駐リンク監視から依頼された記録の終了であれば終了理由とともに監視へ終了を1回だけ返し、
    /// 手動接続で始めた記録の終了であれば手動のアダプター使用を終えたことを1回伝えます。
    /// - Parameter reason: テレメトリの終了理由。
    func telemetryDidEnd(reason: ConnectionSessionEndReason) {
        if phase == .recording {
            phase = .idle
            notifySupervisedRecordingFinished(endReason: reason)
        } else if manualAdapterUse == .recording {
            endManualAdapterUse()
        }
    }

    /// 車両照合の結果から記録を始めます。
    ///
    /// 責務: 古い世代の結果を捨て、照合結果の車両(失敗時は車両なし)でセッション必須の記録開始を試みます。
    /// - Parameters:
    ///   - result: 照合結果。
    ///   - request: 常駐リンク監視からの記録開始要求。
    ///   - generation: 照合を始めた時の世代。
    private func vehicleLookupDidFinish(
        _ result: Result<VehicleProfile?, any Error>,
        for request: AdapterLinkRecordingStartRequest,
        generation: UInt64
    ) {
        guard generation == lookupGeneration, phase == .resolvingVehicle else { return }
        lookupTask = nil
        let vehicle: VehicleProfile?
        switch result {
        case let .success(found):
            lastVehicleLookupError = nil
            vehicle = found
        case let .failure(error):
            lastVehicleLookupError = error
            diagnostics?.vehicleLookupFailed(error)
            vehicle = nil
        }
        if begin(.residentLink(request, vehicle: vehicle), requirement: .required) {
            phase = .recording
        } else {
            phase = .idle
            notifySupervisedRecordingFinished(endReason: nil)
        }
    }

    /// 接続セッションを準備してテレメトリを始めます。
    ///
    /// 責務: テレメトリの開始手段とセッションの要件を確かめ、満たす時だけテレメトリを始めます。
    /// - Parameters:
    ///   - request: 記録開始要求。
    ///   - requirement: セッションを開始できなかった時の方針。
    /// - Returns: テレメトリを始めたら `true`。
    private func begin(_ request: VehicleRecordingStartRequest, requirement: VehicleRecordingSessionRequirement) -> Bool {
        guard let startTelemetry else { return false }
        let hasSession = startSession.execute(request)
        guard hasSession || requirement == .optional else { return false }
        startTelemetry(request)
        return true
    }

    /// 手動接続の開始で置き換えられる、常駐リンク監視から依頼された記録を終了扱いにします。
    ///
    /// 責務: 照合中なら照合を捨て、記録中ならテレメトリの置き換えを待たずに監視へ終了を返します。
    private func endSupervisedRecordingForReplacement() {
        guard phase != .idle else { return }
        cancelVehicleLookup()
        phase = .idle
        notifySupervisedRecordingFinished(endReason: nil)
    }

    /// 進行中の車両照合を捨てます。
    ///
    /// 責務: 世代を進めて照合結果が反映されないようにし、照合タスクをキャンセルします。
    private func cancelVehicleLookup() {
        lookupGeneration &+= 1
        lookupTask?.cancel()
        lookupTask = nil
    }

    /// 常駐リンク監視からの記録開始要求を断ります。
    ///
    /// 責務: 理由を状態と診断記録へ残し、何も始めずに監視へ終了を返します。
    /// - Parameter reason: 断った理由。
    private func declineRecordingStart(_ reason: VehicleRecordingStartDeclineReason) {
        lastStartDeclineReason = reason
        diagnostics?.recordingStartDeclined(reason)
        notifySupervisedRecordingFinished(endReason: nil)
    }

    /// 手動のアダプター使用を終えます。
    ///
    /// 責務: 段階を `idle` へ戻し、使い終えたことを常駐リンク監視へ伝えます。
    private func endManualAdapterUse() {
        manualAdapterUse = .idle
        manualAdapterUseDidEnd?()
    }

    /// 常駐リンク監視へ記録の終了を返します。
    ///
    /// 責務: 設定済みの終了通知先を終了理由つきで1回呼びます。
    /// - Parameter endReason: 記録中から終わった時のテレメトリ終了理由。それ以外は `nil`。
    private func notifySupervisedRecordingFinished(endReason: ConnectionSessionEndReason?) {
        supervisedRecordingDidFinish?(endReason)
    }
}
