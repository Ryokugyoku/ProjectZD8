/// 常駐リンク監視の遷移結果としてユースケースが実行する作用です。配列の順に実行します。
nonisolated enum AdapterLinkSupervisionEffect: Equatable, Sendable {
    /// 指定した既定アダプター設定で常駐リンクを開始します。
    case startLink(DefaultAdapterPreference)

    /// 常駐リンクを停止します。
    case stopLink

    /// 車両検知通知の許可・カテゴリ・[記録開始]の受け口を準備します(初回だけ実行されます)。
    case prepareNotifications

    /// 進行中の初期化・車両確認・待機・VIN読取を取り消し、後から届く結果を無視させます。
    case cancelOperations

    /// アダプターのチップ種別とATMA対応可否を判定します。
    case initializeAdapter

    /// 指定したタイムアウトでECUの応答を確認します。
    case confirmVehicle(VehicleResponseTimeout)

    /// 指定した時間だけ待ってから次の再確認を促します(`vehicleConfirmationIntervalElapsed` を入力します)。
    case scheduleVehicleConfirmation(after: Duration)

    /// 自動記録設定を読み込んだ上でVINを読み取ります。
    case readVIN

    /// 「車両を検知しました」通知を提示します。
    case presentVehicleDetected(vin: String?)

    /// 「記録を開始しました」通知を提示します。
    case presentRecordingStarted(vin: String?)

    /// 提示中の車両検知通知・記録開始通知を取り下げます。
    case dismissNotification

    /// 記録側へ記録開始を要求します。
    case requestRecordingStart(AdapterLinkRecordingStartRequest)

    /// 記録側へ記録停止を要求します。
    case requestRecordingStop

    /// 終了処理の完了を状態機械へ通知します(`finishingDidComplete` を入力します)。
    case completeFinishing
}
