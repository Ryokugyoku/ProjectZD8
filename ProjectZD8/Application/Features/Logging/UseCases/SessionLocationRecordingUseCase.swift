import Foundation

/// 接続セッション中の位置記録の開始・停止と、位置記録の状態変化(事象行)の唯一の書き手です。
///
/// - 現在のセッション・設定・許可・前面かどうか・取得可否を持ち、変わるたびに `SessionLocationRecordingPolicy` で判定します。
/// - 取得すると判定したら位置の流れを購読して保存役へ流し、取得しないと判定したら購読を取消します。
/// - 事象行は、セッションがある間、判定の種類が直前に書いた種類と変わった時だけ書きます(セッションが替わったら必ず書きます)。
/// - 事象行の保存失敗は診断へ残します。失敗した種類も書いた扱いにし、同じ失敗を繰り返し書こうとしません。
@MainActor
final class SessionLocationRecordingUseCase {
    /// 位置の流れを購読する口です。
    private let locations: any LocationUpdateSubscriptionPort
    /// 位置を保存する受け手です。
    private let recorder: ConnectionSessionLocationRecorder
    /// 事象行の保存先です。
    private let repository: any ConnectionSessionLocationRepository
    /// 保存の失敗を残す診断です。
    private let diagnostics: any SessionLocationRecordingDiagnosticsPort
    /// 取得の要否と状態の種類を決める判定です。
    private let policy: SessionLocationRecordingPolicy
    /// 現在時刻を返す処理です。
    private let now: () -> Date

    /// 記録中の接続セッションです。記録中でなければ `nil`。
    private var sessionID: ConnectionSessionID?
    /// 利用者の設定で記録がオンなら `true`。
    private var isRecordingEnabled: Bool
    /// 現在の位置情報の許可状態です。
    private var permission: LocationPermission
    /// アプリが前面なら `true`。
    private var isForeground: Bool
    /// 購読中の流れで位置を取得できているなら `true`。購読を始める時は「取得可」とみなします。
    private var isLocationAvailable = true
    /// 現在のセッションで直前に書いた(書こうとした)状態の種類です。
    private var lastWrittenEventKind: ConnectionSessionLocationEventKind?
    /// 位置の流れを保存役へ流すタスクです。購読していなければ `nil`。
    private var recordingTask: Task<Void, Never>?
    /// 購読の世代です。取消した古い購読からの報告を無視するために使います。
    private var subscriptionGeneration = 0

    /// 境界・初期状態・判定・時刻を注入して生成します。
    ///
    /// 責務: 位置記録の制御に必要な副作用と、セッション外で保持する初期状態を固定します。
    /// - Parameters:
    ///   - locations: 位置の流れを購読する口。
    ///   - recorder: 位置を保存する受け手。
    ///   - repository: 事象行の保存先。
    ///   - diagnostics: 保存の失敗を残す診断。
    ///   - isRecordingEnabled: 利用者の設定で記録がオンなら `true`。
    ///   - permission: 現在の位置情報の許可状態。
    ///   - isForeground: アプリが前面なら `true`。
    ///   - policy: 取得の要否と状態の種類を決める判定。
    ///   - now: 現在時刻を返す処理。
    init(
        locations: any LocationUpdateSubscriptionPort,
        recorder: ConnectionSessionLocationRecorder,
        repository: any ConnectionSessionLocationRepository,
        diagnostics: any SessionLocationRecordingDiagnosticsPort,
        isRecordingEnabled: Bool,
        permission: LocationPermission,
        isForeground: Bool,
        policy: SessionLocationRecordingPolicy = .init(),
        now: @escaping () -> Date = Date.init
    ) {
        self.locations = locations
        self.recorder = recorder
        self.repository = repository
        self.diagnostics = diagnostics
        self.isRecordingEnabled = isRecordingEnabled
        self.permission = permission
        self.isForeground = isForeground
        self.policy = policy
        self.now = now
    }

    /// 購読中のタスクを取消します。
    deinit {
        recordingTask?.cancel()
    }

    /// 記録中のセッションの変化を反映します。
    ///
    /// 責務: 同じ ID の連続通知は無視し、替わったら購読と状態を初期化して新しいセッションで判定し直します。
    /// - Parameter sessionID: 新しい記録中のセッション。記録中でなければ `nil`。
    func activeSessionDidChange(_ sessionID: ConnectionSessionID?) {
        guard sessionID != self.sessionID else { return }
        stopAcquiring()
        self.sessionID = sessionID
        isLocationAvailable = true
        lastWrittenEventKind = nil
        reevaluate()
    }

    /// 位置情報の許可状態の変化を反映します。
    ///
    /// 責務: 新しい許可状態を保持して判定し直します。
    /// - Parameter permission: 新しい許可状態。
    func permissionDidChange(_ permission: LocationPermission) {
        self.permission = permission
        reevaluate()
    }

    /// アプリの前面・背面の変化を反映します。
    ///
    /// 責務: 前面かどうかを保持して判定し直します。
    /// - Parameter isForeground: アプリが前面なら `true`。
    func foregroundDidChange(isForeground: Bool) {
        self.isForeground = isForeground
        reevaluate()
    }

    /// 利用者の記録設定の変化を反映します。
    ///
    /// 責務: 記録設定を保持して判定し直します。
    /// - Parameter isEnabled: 記録がオンなら `true`。
    func recordingPreferenceDidChange(isEnabled: Bool) {
        isRecordingEnabled = isEnabled
        reevaluate()
    }

    /// 現在の状態で判定し、購読の開始・停止と事象行の書込みを行います。
    ///
    /// 責務: セッションがある時だけ、判定に従って購読を合わせ、状態の種類が変わっていれば事象行を書きます。
    private func reevaluate() {
        guard let sessionID else { return }
        if currentDecision().acquiresLocation {
            startAcquiringIfNeeded(for: sessionID)
        } else {
            stopAcquiring()
        }
        writeEventIfChanged(currentDecision().eventKind, for: sessionID)
    }

    /// 保持している状態から判定結果を返します。
    ///
    /// 責務: 設定・許可・前面かどうか・取得可否を判定へ渡します。
    /// - Returns: 取得の要否と状態の種類。
    private func currentDecision() -> SessionLocationRecordingDecision {
        policy.decision(
            isRecordingEnabled: isRecordingEnabled,
            permission: permission,
            isForeground: isForeground,
            isLocationAvailable: isLocationAvailable
        )
    }

    /// 購読していなければ、位置の流れを購読して保存役へ流し始めます。
    ///
    /// 責務: 二重購読を避け、新しい世代で購読を1本作り、取得可否を「取得可」から始めます。
    /// - Parameter sessionID: 位置を保存する接続セッション。
    private func startAcquiringIfNeeded(for sessionID: ConnectionSessionID) {
        guard recordingTask == nil else { return }
        subscriptionGeneration += 1
        let generation = subscriptionGeneration
        isLocationAvailable = true
        let updates = locations.subscribe()
        let recorder = self.recorder
        let availabilityDidChange: @MainActor @Sendable (Bool) -> Void = { [weak self] isAvailable in
            self?.locationAvailabilityDidChange(isAvailable, generation: generation)
        }
        recordingTask = Task { [weak self] in
            await recorder.record(updates, sessionID: sessionID, availabilityDidChange: availabilityDidChange)
            self?.recordingDidFinish(generation: generation)
        }
    }

    /// 購読を取消します。
    ///
    /// 責務: 保存役へ流すタスクを取消し、古い世代からの報告を無視させます。
    private func stopAcquiring() {
        guard let recordingTask else { return }
        recordingTask.cancel()
        self.recordingTask = nil
        subscriptionGeneration += 1
    }

    /// 保存役からの取得可否の変化を反映します。
    ///
    /// 責務: 現在の購読からの報告だけを取り込み、判定し直します。
    /// - Parameters:
    ///   - isAvailable: 位置を取得できているなら `true`。
    ///   - generation: 報告した購読の世代。
    private func locationAvailabilityDidChange(_ isAvailable: Bool, generation: Int) {
        guard generation == subscriptionGeneration, recordingTask != nil else { return }
        isLocationAvailable = isAvailable
        reevaluate()
    }

    /// 流れが終わって保存役が戻った時に、購読を外します。
    ///
    /// 責務: 現在の購読が自分から終わった場合だけ、次の状態変化で購読し直せるようにタスクを外します。
    /// - Parameter generation: 終わった購読の世代。
    private func recordingDidFinish(generation: Int) {
        guard generation == subscriptionGeneration else { return }
        recordingTask = nil
    }

    /// 状態の種類が直前と変わっていれば事象行を書きます。
    ///
    /// 責務: 同じ種類を続けて書かず、保存の失敗は診断へ残します。
    /// - Parameters:
    ///   - kind: 判定された状態の種類。
    ///   - sessionID: 事象行を所有する接続セッション。
    private func writeEventIfChanged(_ kind: ConnectionSessionLocationEventKind, for sessionID: ConnectionSessionID) {
        guard kind != lastWrittenEventKind else { return }
        lastWrittenEventKind = kind
        do {
            try repository.appendEvent(kind, occurredAt: now(), for: sessionID)
        } catch {
            diagnostics.eventStorageFailed(kind, sessionID: sessionID, error: error)
        }
    }
}
