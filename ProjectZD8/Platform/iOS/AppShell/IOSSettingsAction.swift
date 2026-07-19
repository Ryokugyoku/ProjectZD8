#if os(iOS)
/// iOS設定画面からAppShellへ通知する表示およびアダプター選択操作です。
enum IOSSettingsAction: Equatable {
    /// 表示言語の選択変更を通知します。
    case languageSelected(IOSSettingsLanguage)

    /// 外観モードの選択変更を通知します。
    case appearanceSelected(IOSSettingsAppearance)

    /// 指定スロットへ割り当てるBluetoothアダプターの選択開始を通知します。
    case adapterSelectionRequested(AdapterConnectionRole)

    /// Bluetooth候補の再探索を通知します。
    case bluetoothRefreshRequested

    /// 1件のBluetooth候補について接続情報の確認を通知します。
    case adapterCandidateSelected(DiscoveredAdapter)

    /// 詳細表示中の候補を選択対象のアダプタースロットへ確定します。
    case inspectedAdapterConfirmed

    /// 詳細表示中の候補を設定せず選択画面を閉じます。
    case inspectedAdapterDeclined

    /// Bluetooth候補の接続情報詳細だけを閉じます。
    case adapterDetailsDismissed

    /// 選択対象のアダプター設定を変更せず終了します。
    case adapterSelectionCancelled
}
#endif
