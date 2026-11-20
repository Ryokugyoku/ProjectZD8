import Observation

/// 現在の接続セッション・位置情報の許可・前面かどうかの変化を、走行ルート記録のユースケースと設定モデルへ伝えます。
///
/// 記録の判断は `SessionLocationRecordingUseCase` に任せ、この型は状態の観測と事実の受け渡しだけを行います。
/// 現在のセッションは `IOSRecordingSessionActivityDriver` と同じく `withObservationTracking` で観測するため、
/// 作成・続行の採用・終了・アカウント変更のどの経路で変わっても1か所で拾えます。
/// 画面の表示を待たずに観測するため、BLE の状態復元による背面起動で始まった記録にも効きます。
@MainActor
final class SessionLocationRecordingDriver {
    /// 位置記録の開始・停止を決めるユースケースです。
    private let useCase: SessionLocationRecordingUseCase
    /// 現在の接続セッションを観測するライフサイクルのモデルです。
    private let lifecycle: ConnectionSessionLifecycleModel
    /// 位置情報の許可の読取と変化の流れの境界です。
    private let authorization: any LocationAuthorizationPort
    /// 設定画面の「走行ルートを記録」区画のモデルです。
    private let settings: RouteRecordingSettingsModel
    /// 許可の変化の流れを読むタスクです。`launch()` の前は `nil`。
    private var permissionTask: Task<Void, Never>?
    /// `launch()` を呼んだ後なら `true`。二重の観測を防ぎます。
    private var isLaunched = false

    /// 事実の送り先と観測元を固定して生成します。
    ///
    /// 責務: ユースケース・ライフサイクル・許可の境界・設定モデルを結び付けます。観測は `launch()` で始めます。
    /// - Parameters:
    ///   - useCase: 位置記録の開始・停止を決めるユースケース。
    ///   - lifecycle: 現在の接続セッションを観測するライフサイクルのモデル。
    ///   - authorization: 位置情報の許可の読取と変化の流れの境界。
    ///   - settings: 許可の変化を伝える設定モデル。
    init(
        useCase: SessionLocationRecordingUseCase,
        lifecycle: ConnectionSessionLifecycleModel,
        authorization: any LocationAuthorizationPort,
        settings: RouteRecordingSettingsModel
    ) {
        self.useCase = useCase
        self.lifecycle = lifecycle
        self.authorization = authorization
        self.settings = settings
    }

    /// 許可の変化の流れを読むタスクを取消します。
    deinit {
        permissionTask?.cancel()
    }

    /// 現在の許可とセッションを伝え、以後の変化の観測を始めます。アプリ起動時(BLEの状態復元による背面起動を含む)に呼びます。
    ///
    /// 責務: 2回目以降の呼出しは無視し、許可の流れを先に受け取ってから現在の許可とセッションを反映し、両方の観測を始めます。
    func launch() {
        guard !isLaunched else { return }
        isLaunched = true
        let permissions = authorization.permissionChanges()
        permissionDidChange(authorization.currentPermission)
        observeActiveSession()
        permissionTask = Task { [weak self] in
            for await permission in permissions {
                self?.permissionDidChange(permission)
            }
        }
    }

    /// アプリが前面へ戻ったこと(scenePhase が active)を伝えます。
    ///
    /// 責務: 前面復帰をユースケースの入力へ写します。
    func appDidBecomeActive() {
        useCase.foregroundDidChange(isForeground: true)
    }

    /// アプリが背面へ移ったこと(scenePhase が background)を伝えます。
    ///
    /// 責務: 背面移行をユースケースの入力へ写します。
    func appDidEnterBackground() {
        useCase.foregroundDidChange(isForeground: false)
    }

    /// 許可状態をユースケースと設定モデルの両方へ伝えます。
    ///
    /// 責務: 1件の許可状態を、記録の判定の入力と設定画面の操作へ写します。
    /// - Parameter permission: 新しい許可状態。
    private func permissionDidChange(_ permission: LocationPermission) {
        useCase.permissionDidChange(permission)
        settings.send(.permissionChanged(permission))
    }

    /// 現在のセッションの識別子を伝え、次の変化を1回だけ観測します。変化のたびに観測を登録し直します。
    ///
    /// 責務: 識別子の読み取りを観測へ登録し、現在値をユースケースへ渡し、変化後にメインアクターで繰り返します。
    private func observeActiveSession() {
        let sessionID = withObservationTracking {
            lifecycle.activeSession?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeActiveSession() }
        }
        useCase.activeSessionDidChange(sessionID)
    }
}
