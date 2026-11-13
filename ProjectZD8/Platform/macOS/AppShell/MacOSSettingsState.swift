#if os(macOS)
/// macOS設定画面へ渡すConnection専用の選択状態です。
struct MacOSSettingsState: Equatable {
    /// 接続役割ごとに現在選択されているアダプターです。
    var selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter] = [:]

    /// 次回起動時も優先するプライマリーアダプター設定です。
    var defaultAdapterPreference: DefaultAdapterPreference?

    /// アダプター候補一覧で選択中の接続方式です。
    var adapterTransportMode: AdapterTransportMode = .usb

    /// 選択中の接続方式で検出したアダプター候補です。
    var discoveredAdapters: [DiscoveredAdapter] = []

    /// 現在のアダプター探索状態です。
    var adapterDiscoveryStatus: MacOSAdapterDiscoveryStatus = .idle

    /// 現在アダプター選択シートを表示している接続役割です。
    var presentedAdapterSlot: AdapterConnectionRole?

    /// 接続情報の詳細を確認しているアダプター候補です。
    var inspectedAdapter: DiscoveredAdapter?

    /// 詳細表示中の候補が別の接続役割へ割り当て済みかどうかです。
    var hasAdapterAssignmentConflict = false

    /// HOMEの「アダプターを設定」ボタンを押すたびに増える強調要求番号です。
    var adapterAttentionSequence: UInt = 0

    /// 設定画面が1回だけ表示済みとして消費した強調要求番号です。
    var consumedAdapterAttentionSequence: UInt = 0

    /// 直前の「アダプターを設定」ボタン押下に対して1回だけ処理すべき強調要求が残っているかどうかです。
    var hasPendingAdapterAttention: Bool {
        adapterAttentionSequence > consumedAdapterAttentionSequence
    }
}

/// macOS設定画面に表示するアダプター探索状態です。
enum MacOSAdapterDiscoveryStatus: Equatable {
    /// 探索をまだ開始していません。
    case idle

    /// システムへアダプター候補を問い合わせています。
    case searching

    /// 最新の探索が完了しました。
    case loaded

    /// システムのデバイス情報へアクセスできませんでした。
    case failed
}

#endif
