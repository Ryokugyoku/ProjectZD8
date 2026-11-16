import Foundation

/// 常駐BLEリンク上で車両を検知して記録を始めるまでの監視段階です。
nonisolated enum AdapterLinkSupervisionState: Equatable, Sendable {
    /// リンクの `ready` かアプリ前面復帰を待っています。稼働条件を満たさない間もこの段階です。
    case standby

    /// リンクが `ready` になり、アダプターのチップ種別とATMA対応可否を判定しています。
    ///
    /// `linkReadyAt` は車両確認窓の起点です(前面復帰からの再開では再開時刻)。
    case initializing(linkReadyAt: Date)

    /// ECUの応答を確認しています。低頻度確認中か休止中かを保持します。
    case confirmingVehicle(AdapterLinkVehicleConfirmation)

    /// ECUの応答を確認して車両を検知しました。VIN読取中か記録開始操作待ちかを保持します。
    case vehicleDetected(AdapterLinkDetectedVehicle, phase: AdapterLinkVehicleDetectionPhase)

    /// 記録の開始を要求し、記録側からの終了通知を待っています。
    case recording(AdapterLinkDetectedVehicle)

    /// 記録の停止を要求したか終了通知を受け、待機へ戻る直前です。
    case finishing

    /// ユーザーが記録を切断した。同じ走行が続いている間は初期化・検知・記録開始をしない。
    ///
    /// 保持中は ECU が応答しているかを見張り(`AdapterLinkHeldWatch`)、無応答が連続2回で走行の終わりとみなして初期化からやり直す。
    /// リンクが切れるか稼働条件でリンクを張り直しても待機へ戻る。リンクが `ready` でない間に切断した場合はリンク待ちの保持
    /// (`AdapterLinkHeldWatchPhase.awaitingLink`)で、切断から3分以内にリンクが戻れば見張りを始め、超えて戻れば検知からやり直す。
    case heldAfterUserStop(AdapterLinkHeldWatch)

    /// ユーザー切断後の抑止中かどうかです。
    ///
    /// 責務: 見張りの進行状況に関係なく、抑止状態であることを判定します。
    var isHeldAfterUserStop: Bool {
        if case .heldAfterUserStop = self { return true }
        return false
    }
}
