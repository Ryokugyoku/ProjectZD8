#if os(iOS)
/// iOS設定画面からAppShellへ通知するConnection操作です。
enum IOSSettingsAction: Equatable {
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

    /// HOMEの「アダプターを設定」ボタンを押すたびに遷移先で1回だけ行う注目要求を通知します。
    case adapterAttentionRequested

    /// 指定した注目要求の強調表示が完了したことを通知します。
    case adapterAttentionConsumed(UInt)
}
#endif
