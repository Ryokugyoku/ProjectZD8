import Observation

/// 接続セッションの開始・続行の採用・車両の確定・終了を、車両管理(Garageの「接続中」表示)へ伝える配線です。
///
/// `ConnectionSessionLifecycleModel.activeSession` の識別子と車両IDの組を観測し、組が変わるたびに
/// `VehicleManagementAction.connectionSessionActivityChanged` を送ります。`activeSession` そのものを見るのは、
/// 終了を保存した後に `nil` になった時点で伝えるためです(履歴の再読込の通知は `nil` になる前に呼ばれます)。
/// 車両IDも比べるのは、セッション開始より後に車両が確定した時(識別子は同じまま)にも集計を読み直すためです。
/// 同じセッションへの距離の保存など、識別子も車両も変わらない更新では送りません。iOSとmacOSで共通です。
@MainActor
enum ConnectionSessionActivityRelay {
    /// 伝えるかどうかを比べる、現在セッションの識別子と車両IDの組です。
    private nonisolated struct SessionActivity: Equatable, Sendable {
        /// 現在セッションの識別子です。
        let sessionID: ConnectionSessionID
        /// 現在セッションへ関連付いた車両のIDです。車両が未確定なら `nil` です。
        let vehicleID: VehicleID?

        /// 現在セッションから比べる組を作ります。
        ///
        /// 責務: 1件の現在セッションを、伝えるかどうかの比較に使う識別子と車両IDの組へ写します。
        /// - Parameter session: 現在セッション。
        init(_ session: ConnectionSession) {
            sessionID = session.id
            vehicleID = session.vehicle?.id
        }
    }

    /// 接続セッションの観測を始めます。ルートのモデルを組み立てた時に1回だけ呼びます。
    ///
    /// 責務: 現在の組を伝え済みの値として観測を始めます(開始時点では送りません)。両モデルは弱参照で保持します。
    /// - Parameters:
    ///   - lifecycle: 観測する接続セッションのライフサイクルのモデル。
    ///   - vehicleManagement: 変化を伝える車両管理のモデル。
    static func start(lifecycle: ConnectionSessionLifecycleModel, vehicleManagement: VehicleManagementModel) {
        relay(
            lifecycle: lifecycle,
            vehicleManagement: vehicleManagement,
            delivered: lifecycle.activeSession.map(SessionActivity.init)
        )
    }

    /// 次の変化の観測を登録し、伝え済みの組から変わっていれば車両管理へ伝えます。
    ///
    /// 責務: 現在の組を読み、次の変化の観測を登録し直してから、組が変わった時だけ操作を1件送ります。
    /// 変化はメインアクターへ戻してから処理し、まとめて起きた変化(別のセッションへの置き換えなど)も最新の値で1回伝えます。
    /// - Parameters:
    ///   - lifecycle: 観測する接続セッションのライフサイクルのモデル。
    ///   - vehicleManagement: 変化を伝える車両管理のモデル。
    ///   - delivered: 最後に伝えた(または観測開始時の)現在セッションの組。セッションが無ければ `nil`。
    private static func relay(
        lifecycle: ConnectionSessionLifecycleModel,
        vehicleManagement: VehicleManagementModel,
        delivered: SessionActivity?
    ) {
        let current = lifecycle.activeSession.map(SessionActivity.init)
        withObservationTracking {
            _ = lifecycle.activeSession
        } onChange: { [weak lifecycle, weak vehicleManagement] in
            Task { @MainActor in
                guard let lifecycle, let vehicleManagement else { return }
                relay(lifecycle: lifecycle, vehicleManagement: vehicleManagement, delivered: current)
            }
        }
        guard current != delivered else { return }
        vehicleManagement.send(.connectionSessionActivityChanged(isSessionActive: current != nil))
    }
}
