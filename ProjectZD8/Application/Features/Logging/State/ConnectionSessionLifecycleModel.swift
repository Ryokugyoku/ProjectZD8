import Foundation
import Observation

/// 接続セッションの開始、車両関連付け、終了を永続化へ結び付けます。
///
/// プロセス復帰時に未終了だったセッションは `RecoverRelaunchedConnectionSessionUseCase` で処理し、猶予内なら
/// 続行可能なセッションとして保持します(`activeSession` にはしません)。次の接続開始で同じ車両が確定し、
/// その時点でも猶予内(実時間)なら同じセッションを続け、そうでなければ続行可能だったセッションを終了して新規に開始します。
/// 未登録車両の接続(`vehicleUnregistered`)では、続行可能なセッションも車両なしの場合だけ続けます(`ConnectionSessionResumptionMatcher`)。
/// 取得の一時停止中はLiveTelemetryから終了が通知されないため、セッションは終了扱いになりません。
@MainActor
@Observable
final class ConnectionSessionLifecycleModel {
    /// 現在接続中として管理しているセッションです。
    private(set) var activeSession: ConnectionSession?
    /// セッションの永続化境界です。
    @ObservationIgnored private let repository: any ConnectionSessionRepository
    /// 未デコードOBD応答の永続化境界です。
    @ObservationIgnored private let rawLogRepository: (any ConnectionSessionRawLogRepository)?
    /// sessionと取得証拠を部分成功なしで終了・回復する境界です。
    @ObservationIgnored private let acquisitionTerminationRepository: (any ConnectionSessionAcquisitionTerminationRepository)?
    /// 現在日時を生成する注入済み処理です。
    @ObservationIgnored private let now: () -> Date
    /// 新規セッションIDを生成する注入済み処理です。
    @ObservationIgnored private let makeID: () -> ConnectionSessionID
    /// 新しいセッションへ固定する現在端末情報です。
    @ObservationIgnored private let acquisitionDevice: ConnectionSessionAcquisitionDevice?
    /// 履歴の再読込が必要になったことを通知する処理です。
    @ObservationIgnored private let historyDidChange: @MainActor () -> Void
    /// 終了済みセッションのiCloudアップロード要求を通知する処理です。
    @ObservationIgnored private let endedSessionUploadRequested: @MainActor (ConnectionSession) -> Void
    /// 現在のAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?
    /// セッション終了時にiCloudアップロードを要求するかを示します。
    @ObservationIgnored private var automaticUploadEnabled: Bool
    /// 現在セッションの走行距離差分へ採用している累積距離取得元です。
    @ObservationIgnored private var selectedDistanceSource: ConnectionSessionDistanceSource?
    /// プロセス復帰時の未終了セッションを処理するuse caseです。未設定なら従来どおりアカウント単位で異常終了します。
    @ObservationIgnored private let recoverRelaunchedSession: RecoverRelaunchedConnectionSessionUseCase?
    /// プロセス復帰後に続行可能として保持しているセッションです。
    @ObservationIgnored private var resumableSession: ConnectionSession?
    /// 続行可能なセッションの最後にcommitしたRawの観測時刻です。
    @ObservationIgnored private var resumableLastCommittedAt: Date?
    /// 接続開始を受け、続行するかを車両の確定まで保留しているかどうかです。
    @ObservationIgnored private var isAwaitingResumeDecision = false
    /// 続行可能なセッションを次の接続で続けるかの判定です。
    @ObservationIgnored private let resumptionMatcher = ConnectionSessionResumptionMatcher()

    /// セッション保存先と副作用依存を固定して生成します。
    ///
    /// 責務: 接続ライフサイクル操作を1件のセッション永続化境界へ結び付けます。
    /// - Parameters:
    ///   - repository: セッションの保存と取得を行う境界。
    ///   - rawLogRepository: 数値化前のOBD応答を追記する境界。
    ///   - acquisitionTerminationRepository: sessionと取得証拠を部分成功なしで終了・回復する境界。
    ///   - now: 開始日時と終了日時を生成する処理。
    ///   - makeID: 新しいセッションIDを生成する処理。省略時はUUIDを生成します。
    ///   - acquisitionDevice: 新しいセッションへ固定する現在端末情報。
    ///   - historyDidChange: 保存後に履歴再読込を通知する処理。
    ///   - automaticUploadEnabled: 終了時のiCloud自動アップロード初期値。
    ///   - endedSessionUploadRequested: 自動アップロード対象の終了済みセッション通知先。
    ///   - recoverRelaunchedSession: プロセス復帰時の未終了セッションを処理するuse case。
    init(
        repository: any ConnectionSessionRepository,
        rawLogRepository: (any ConnectionSessionRawLogRepository)? = nil,
        acquisitionTerminationRepository: (any ConnectionSessionAcquisitionTerminationRepository)? = nil,
        now: @escaping () -> Date = Date.init,
        makeID: (() -> ConnectionSessionID)? = nil,
        acquisitionDevice: ConnectionSessionAcquisitionDevice? = nil,
        historyDidChange: @escaping @MainActor () -> Void = {},
        automaticUploadEnabled: Bool = false,
        endedSessionUploadRequested: @escaping @MainActor (ConnectionSession) -> Void = { _ in },
        recoverRelaunchedSession: RecoverRelaunchedConnectionSessionUseCase? = nil
    ) {
        self.repository = repository
        self.rawLogRepository = rawLogRepository
        self.acquisitionTerminationRepository = acquisitionTerminationRepository
        self.now = now
        self.makeID = makeID ?? { ConnectionSessionID() }
        self.acquisitionDevice = acquisitionDevice
        self.historyDidChange = historyDidChange
        self.automaticUploadEnabled = automaticUploadEnabled
        self.endedSessionUploadRequested = endedSessionUploadRequested
        self.recoverRelaunchedSession = recoverRelaunchedSession
    }

    /// 型付き操作をセッション永続化へ変換します。
    ///
    /// 責務: 1件のLogging操作を対応するライフサイクル変更へ振り分けます。
    /// - Parameter action: AppまたはApplicationから通知された操作。
    func send(_ action: ConnectionSessionLifecycleAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case let .automaticUploadChanged(isEnabled): automaticUploadEnabled = isEnabled
        case .startRequested: startSession()
        case let .vehicleResolved(vehicle): bindVehicle(vehicle)
        case .vehicleUnregistered: if isAwaitingResumeDecision { resolveResumption(forVehicleID: nil) }
        case let .unregisteredVehicleRegistered(vehicle): bindLaterRegisteredVehicle(vehicle)
        case let .distanceObserved(observation): recordDistance(observation)
        case let .endRequested(reason, endedAt): endSession(reason: reason, endedAt: endedAt)
        }
    }

    /// 数値化前のOBD応答を現在セッションへ追記します。
    ///
    /// 責務: 1件の未デコードOBD応答を現在の接続セッションへ関連付けて永続化します。
    /// - Parameter observation: 取得境界から受け取った未デコードOBD応答。
    /// - Throws: 接続セッション不在またはRawログ永続化に失敗した場合のエラー。
    func recordRawResponse(_ observation: OBDRawResponseObservation) throws {
        guard let sessionID = activeSession?.id, let rawLogRepository else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        try rawLogRepository.append(observation, to: sessionID)
    }

    /// 新しいアカウントを有効化し、残存中セッションを異常終了へ閉じます。
    ///
    /// 責務: 1件のアカウント変更をセッション保存範囲と再起動回復へ反映します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        activeSession = nil
        selectedDistanceSource = nil
        clearResumableSession()
        guard let identifier, !identifier.isEmpty else { return }
        do {
            let unfinished = try repository.sessions(for: identifier).filter { $0.endedAt == nil }
            guard !unfinished.isEmpty else { return }
            let recoveredAt = now()
            let endedSessions: [ConnectionSession]
            if let recoverRelaunchedSession {
                endedSessions = try recoverRelaunched(unfinished, using: recoverRelaunchedSession, at: recoveredAt)
            } else if let acquisitionTerminationRepository {
                endedSessions = try acquisitionTerminationRepository.recoverInterruptedSessionAcquisitions(
                    for: identifier,
                    recoveredAt: recoveredAt
                )
            } else {
                endedSessions = try unfinished.map { session in
                    var ended = session
                    ended.endedAt = recoveredAt
                    ended.endReason = .unexpectedTermination
                    try repository.save(ended)
                    return ended
                }
            }
            if !endedSessions.isEmpty { historyDidChange() }
            if automaticUploadEnabled {
                endedSessions.forEach(endedSessionUploadRequested)
            }
        } catch {
            return
        }
    }

    /// プロセス復帰時の未終了セッションを処理し、終了したものを返します。
    ///
    /// 責務: 各セッションを続行可能か終了かへ振り分け、続行可能なものは最も新しい1件だけを保持して残りを終了します。
    /// - Parameters:
    ///   - unfinished: プロセス復帰時に未終了だったセッション。
    ///   - useCase: プロセス復帰を処理するuse case。
    ///   - recoveredAt: 判定に使う実時間。
    /// - Returns: 終了したセッション。
    /// - Throws: 読取または保存の失敗。
    private func recoverRelaunched(
        _ unfinished: [ConnectionSession],
        using useCase: RecoverRelaunchedConnectionSessionUseCase,
        at recoveredAt: Date
    ) throws -> [ConnectionSession] {
        var ended: [ConnectionSession] = []
        for session in unfinished.sorted(by: { $0.startedAt < $1.startedAt }) {
            switch try useCase.recover(session, now: recoveredAt) {
            case let .ended(endedSession):
                ended.append(endedSession)
            case let .resumable(resumable, lastCommittedAt):
                if let previous = resumableSession, let previousAt = resumableLastCommittedAt {
                    ended.append(try useCase.end(previous, lastCommittedAt: previousAt, now: recoveredAt))
                }
                resumableSession = resumable
                resumableLastCommittedAt = lastCommittedAt
            }
        }
        return ended
    }

    /// 続行可能として保持しているセッションを手放します。
    ///
    /// 責務: 保存済みの状態を変えずに、続行可能なセッションの保持と保留中の判定を消します。
    private func clearResumableSession() {
        resumableSession = nil
        resumableLastCommittedAt = nil
        isAwaitingResumeDecision = false
    }

    /// 現在アカウントへ新しい未終了セッションを保存します。
    ///
    /// 責務: 1回のHOME接続開始を新規セッションとして永続化します。続行可能なセッションがあれば、
    /// 続けるかの判定を車両の確定まで保留します。
    private func startSession() {
        guard let accountIdentifier, !accountIdentifier.isEmpty else { return }
        if activeSession != nil { endSession(reason: .superseded) }
        if resumableSession != nil {
            isAwaitingResumeDecision = true
            return
        }
        createSession(for: accountIdentifier)
    }

    /// 新しい未終了セッションを保存して現在セッションにします。
    ///
    /// 責務: 1件の新規セッションを永続化し、保存できなければ現在セッションを持たない状態にします。
    /// - Parameter accountIdentifier: セッションを所有するアカウント識別子。
    private func createSession(for accountIdentifier: String) {
        let session = ConnectionSession(
            id: makeID(),
            accountIdentifier: accountIdentifier,
            startedAt: now(),
            acquisitionDevice: acquisitionDevice
        )
        do {
            try repository.save(session)
            activeSession = session
            selectedDistanceSource = nil
            historyDidChange()
        } catch {
            activeSession = nil
        }
    }

    /// 確定した登録車両を現在の未終了セッションへ保存します。
    ///
    /// 責務: 1台の登録車両スナップショットを現在セッションへ関連付けます。続行の判定を保留していれば先に判定します。
    /// - Parameter vehicle: 接続対象として確定した登録車両。
    private func bindVehicle(_ vehicle: VehicleProfile) {
        if isAwaitingResumeDecision { resolveResumption(forVehicleID: vehicle.id) }
        guard var session = activeSession else { return }
        session.vehicle = ConnectionSessionVehicle(profile: vehicle)
        do {
            try repository.save(session)
            activeSession = session
            historyDidChange()
        } catch {
            return
        }
    }

    /// 車両なしで始めた現在セッションへ、途中で登録された車両を関連付けます。
    ///
    /// 責務: 現在セッションに車両が無い場合だけ車両を保存します。取得対象とセグメントは変えません。
    /// - Parameter vehicle: 車両なしの接続中に登録された車両。
    private func bindLaterRegisteredVehicle(_ vehicle: VehicleProfile) {
        guard activeSession?.vehicle == nil else { return }
        bindVehicle(vehicle)
    }

    /// 続行可能なセッションを続けるか、終了して新規に開始するかを決めます。
    ///
    /// 責務: 車両が一致(どちらも車両なしを含む)し実時間の猶予内なら続行可能なセッションを現在セッションにし、
    /// それ以外は終了して新規セッションを保存します。
    /// - Parameter vehicleID: 接続対象として確定した登録車両のID。未登録車両なら `nil`。
    private func resolveResumption(forVehicleID vehicleID: VehicleID?) {
        isAwaitingResumeDecision = false
        guard let resumable = resumableSession, let lastCommittedAt = resumableLastCommittedAt,
              let accountIdentifier, !accountIdentifier.isEmpty else { return }
        clearResumableSession()
        let decidedAt = now()
        if resumptionMatcher.canResume(
            resumableVehicleID: resumable.vehicle?.id,
            connectingVehicleID: vehicleID,
            lastCommittedAt: lastCommittedAt,
            now: decidedAt
        ) {
            activeSession = resumable
            selectedDistanceSource = nil
            historyDidChange()
            return
        }
        if let recoverRelaunchedSession {
            do {
                let ended = try recoverRelaunchedSession.end(resumable, lastCommittedAt: lastCommittedAt, now: decidedAt)
                historyDidChange()
                if automaticUploadEnabled { endedSessionUploadRequested(ended) }
            } catch {
                // 終了を保存できなかったセッションは未終了のまま残り、次のアカウント有効化(プロセス復帰の処理)で
                // 猶予切れとして終了します。新しい接続はそれと独立に記録します。
            }
        }
        createSession(for: accountIdentifier)
    }

    /// 優先順位を満たす累積距離の先頭値と最新値を現在セッションへ保存します。
    ///
    /// 責務: 1件の有効な累積距離観測を取得元の優先順位に従ってセッション差分境界へ反映します。
    /// - Parameter observation: 取得元とキロメートル値を保持する累積距離観測。
    private func recordDistance(_ observation: ConnectionSessionDistanceObservation) {
        guard observation.kilometers.isFinite, observation.kilometers >= 0,
              var session = activeSession else { return }
        if let selectedDistanceSource,
           observation.source != selectedDistanceSource,
           !observation.source.hasPriority(over: selectedDistanceSource) {
            return
        }
        if observation.source != selectedDistanceSource {
            session.startingOdometerKilometers = observation.kilometers
            session.endingOdometerKilometers = observation.kilometers
            session.distanceSourceModelCode = observation.vehicleModelCode
        } else {
            guard session.endingOdometerKilometers != observation.kilometers else { return }
            session.endingOdometerKilometers = observation.kilometers
            session.distanceSourceModelCode = observation.vehicleModelCode
        }
        do {
            try repository.save(session)
            activeSession = session
            selectedDistanceSource = observation.source
            historyDidChange()
        } catch {
            return
        }
    }

    /// 現在セッションへ終了日時と原因を保存します。
    ///
    /// 責務: 1件の未終了セッションを指定原因で終端状態へ遷移させます。
    /// - Parameters:
    ///   - reason: セッションが終了した直接原因。
    ///   - requestedEndedAt: 終了時刻。猶予切れでは最後に受信した時刻。`nil` なら処理した時刻を使います。
    private func endSession(reason: ConnectionSessionEndReason, endedAt requestedEndedAt: Date? = nil) {
        guard let currentSession = activeSession else { return }
        let endedAt = requestedEndedAt.map { max($0, currentSession.startedAt) } ?? now()
        do {
            let session: ConnectionSession
            if let acquisitionTerminationRepository {
                session = try acquisitionTerminationRepository.finishSessionAcquisition(
                    currentSession,
                    endedAt: endedAt,
                    reason: reason
                )
            } else {
                var ended = currentSession
                ended.endedAt = endedAt
                ended.endReason = reason
                try repository.save(ended)
                session = ended
            }
            activeSession = nil
            selectedDistanceSource = nil
            historyDidChange()
            if automaticUploadEnabled {
                endedSessionUploadRequested(session)
            }
        } catch {
            activeSession = currentSession
        }
    }
}
