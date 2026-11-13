#if os(iOS)
/// iOS設定画面へ渡すConnection専用の選択状態です。
struct IOSSettingsState: Equatable {
    /// 接続役割ごとに現在選択されているBluetoothアダプター候補です。
    var selectedAdapters: [AdapterConnectionRole: DiscoveredAdapter] = [:]

    /// 次回起動時も優先するプライマリーアダプター設定です。
    var defaultAdapterPreference: DefaultAdapterPreference?

    /// 最新のBluetooth探索で検出した候補です。
    var discoveredAdapters: [DiscoveredAdapter] = []

    /// 現在のBluetooth探索表示状態です。
    var bluetoothDiscoveryStatus: IOSBluetoothDiscoveryStatus = .idle

    /// Bluetoothアダプター選択画面で設定対象にしているスロットです。
    var presentedAdapterSlot: AdapterConnectionRole?

    /// 接続情報の詳細を確認しているBluetooth候補です。
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

/// iOS設定画面に表示するBluetooth探索状態です。
enum IOSBluetoothDiscoveryStatus: Equatable {
    /// Bluetooth探索をまだ開始していません。
    case idle

    /// Bluetooth候補を非同期に探索しています。
    case searching

    /// 最新のBluetooth探索が完了しました。
    case loaded

    /// Bluetoothを利用できない理由が判明しました。
    case unavailable(IOSBluetoothUnavailableReason)

    /// Bluetooth状態以外の理由で探索を完了できませんでした。
    case failed
}

/// iOSでBluetooth探索を利用できない理由を表示用に表します。
enum IOSBluetoothUnavailableReason: Equatable {
    /// Bluetoothがシステム設定で無効です。
    case poweredOff

    /// Bluetooth利用が許可されていません。
    case unauthorized

    /// 実行環境がBluetooth Low Energy中央デバイス機能に対応していません。
    case unsupported
}

#endif
