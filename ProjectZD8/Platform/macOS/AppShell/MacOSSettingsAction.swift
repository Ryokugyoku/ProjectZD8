#if os(macOS)
/// macOS設定画面からAppShellへ通知するConnection操作です。
enum MacOSSettingsAction: Equatable {
    /// 指定した接続役割のアダプター選択開始を通知します。
    case adapterSelectionRequested(AdapterConnectionRole)

    /// アダプター探索に使う接続方式の変更を通知します。
    case adapterTransportModeSelected(AdapterTransportMode)

    /// 現在の接続方式でアダプター候補の再探索を通知します。
    case adapterRefreshRequested

    /// 1件のアダプター候補について接続情報の確認を通知します。
    case adapterCandidateSelected(DiscoveredAdapter)

    /// 詳細表示中の候補をプライマリーアダプターとして確定します。
    case inspectedAdapterConfirmed

    /// 詳細表示中の候補を設定せず選択画面を閉じます。
    case inspectedAdapterDeclined

    /// アダプター接続情報の詳細表示だけを閉じます。
    case adapterDetailsDismissed

    /// プライマリーアダプター選択を変更せず終了します。
    case adapterSelectionCancelled

    /// HOMEの「アダプターを設定」ボタンを押すたびに遷移先で1回だけ行う注目要求を通知します。
    case adapterAttentionRequested

    /// 指定した注目要求の強調表示が完了したことを通知します。
    case adapterAttentionConsumed(UInt)
}
#endif
