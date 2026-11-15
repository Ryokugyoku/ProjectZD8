/// 常駐リンク監視の状態機械へ入力する出来事です。
nonisolated enum AdapterLinkSupervisionEvent: Equatable, Sendable {
    /// 監視の開始・停止、認証状態、既定アダプター設定のいずれかが変わりました。
    ///
    /// 新しい値は同時に渡す `AdapterLinkSupervisionConditions` に入っています。
    case operatingConditionsChanged

    /// 常駐リンクの状態が変わりました。直前の状態は条件の `linkState` に入っています。
    case linkStateChanged(AdapterLinkState)

    /// アダプター初期化が成功し、チップ種別とATMA判定結果が得られました。
    case adapterInitializationSucceeded(AcquisitionAdapterProbeEvidence)

    /// アダプター初期化が失敗しました。
    case adapterInitializationFailed

    /// 車両確認が完了し、ECU応答の有無が得られました。
    case vehicleConfirmationCompleted(VehicleResponseOutcome)

    /// 車両確認が失敗しました。無応答と同じく検知にはしません。
    case vehicleConfirmationFailed

    /// 次の再確認までの待機が終わりました。
    case vehicleConfirmationIntervalElapsed

    /// VIN読取が完了しました。`vin` は読めなかった場合 `nil` です。
    ///
    /// `isAutomaticRecordingEnabled` は検知時点で読み込んだ自動記録設定です。
    case vinReadCompleted(vin: String?, isAutomaticRecordingEnabled: Bool)

    /// VIN読取が失敗しました。検知は成立させ、VINなしで続けます。
    ///
    /// `isAutomaticRecordingEnabled` は検知時点で読み込んだ自動記録設定です。
    case vinReadFailed(isAutomaticRecordingEnabled: Bool)

    /// アプリが前面へ復帰しました。
    case appDidBecomeActive

    /// ユーザーが「車両を検知しました」通知の[記録開始]を選びました。
    case recordingStartSelected

    /// 記録側から記録が終了したと通知されました。
    case recordingDidFinish

    /// 記録終了を受けた終了処理が完了しました。
    case finishingDidComplete

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い始めました。使い終えるまで初期化・車両確認を始めません。
    case externalAdapterUseBegan

    /// 常駐リンク以外の経路(手動接続)がアダプターを使い終えました。
    case externalAdapterUseEnded
}
