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
}
