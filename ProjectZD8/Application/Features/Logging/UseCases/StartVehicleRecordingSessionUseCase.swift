/// 記録開始の接続セッション側の手順(セッション開始・車両または未登録の確定・観測VIN)を1か所にまとめます。
///
/// 手動接続と常駐リンクのどちらから始める記録も、この順序で接続セッションを準備します。
@MainActor
struct StartVehicleRecordingSessionUseCase {
    /// 接続セッションの開始・車両関連付け・観測VINを保持するモデルです。
    private let lifecycle: ConnectionSessionLifecycleModel

    /// 接続セッションのモデルを固定して生成します。
    ///
    /// 責務: 記録開始の手順を送る先を固定します。
    /// - Parameter lifecycle: 接続セッションの開始・車両関連付け・終了を保持するモデル。
    init(lifecycle: ConnectionSessionLifecycleModel) {
        self.lifecycle = lifecycle
    }

    /// 進行中の接続セッションがあるかどうかです。
    var hasActiveSession: Bool {
        lifecycle.activeSession != nil
    }

    /// 記録開始要求に従って接続セッションを開始します。
    ///
    /// 責務: セッションの開始に続けて、車両ありなら車両確定を、車両なしなら未登録の確定を送ります。
    /// プロセス復帰後に続行可能なセッションがある場合、続けるか新規に始めるかはこの確定で決まるため、
    /// 進行中になったかどうかは確定を送った後で確かめます。進行中になった時だけ、観測VINがあれば `vinObserved` を送ります。
    /// - Parameter request: 記録開始要求。
    /// - Returns: 接続セッションが進行中になったら `true`。アカウント未確定や保存失敗で開始できなかったら `false`。
    func execute(_ request: VehicleRecordingStartRequest) -> Bool {
        lifecycle.send(.startRequested)
        if let vehicle = request.vehicle {
            lifecycle.send(.vehicleResolved(vehicle))
        } else {
            lifecycle.send(.vehicleUnregistered)
        }
        guard lifecycle.activeSession != nil else { return false }
        if let observedVIN = request.observedVIN {
            lifecycle.send(.vinObserved(observedVIN))
        }
        return true
    }
}
