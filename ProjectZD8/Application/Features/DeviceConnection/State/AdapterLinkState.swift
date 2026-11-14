/// 登録済みアダプターとの常駐リンクが現在どの段階にあるかを表します。
nonisolated enum AdapterLinkState: Equatable, Sendable {
    /// リンクが開始されていない、またはBluetooth状態の確定を待っています。
    case idle

    /// 登録済みアダプターの広告を待っています。
    case awaitingPeripheral

    /// 登録済みアダプターへの保留中の接続要求を出しています。
    case connecting

    /// 接続後にUARTのServiceとCharacteristicを探索し、Notifyを有効化しています。
    case discovering

    /// Notify有効化の完了を確認し、送受信できる状態です。
    case ready

    /// リンクが切断されています。理由が終端かどうかは `AdapterLinkDisconnectReason.isTerminal` で判定します。
    case disconnected(AdapterLinkDisconnectReason)
}
