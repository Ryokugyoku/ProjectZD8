/// 常駐リンクが `ready` 以外へ落ちた理由を表します。
nonisolated enum AdapterLinkDisconnectReason: Equatable, Sendable {
    /// Bluetoothがシステム設定で無効です。電源が戻れば接続手順をやり直します。
    case bluetoothPoweredOff

    /// Bluetooth利用が許可されていません。許可されれば接続手順をやり直します。
    case bluetoothUnauthorized

    /// 実行環境がBluetooth Low Energy中央役に対応していません。
    case bluetoothUnsupported

    /// 接続済みのペリフェラル側から切断されました。OSのエラー説明を保持します(説明がない場合は `nil`)。
    case peripheralDisconnected(errorDescription: String?)

    /// 保留中の接続要求がOSから失敗として通知されました。OSのエラー説明を保持します。
    case connectionFailed(errorDescription: String?)

    /// Service・Characteristic探索またはNotify有効化が失敗しました。OSのエラー説明を保持します。
    case discoveryFailed(errorDescription: String?)

    /// 既知のUART構成に一致するService・Characteristicがありません。再試行しても変わらない終端の失敗です。
    case unknownUARTProfile

    /// 探索の各段階で応答が待機上限を超えました。
    case discoveryTimedOut

    /// `ready` に到達しないまま再接続が上限回数を超えました。終端の失敗です。
    case retryLimitExceeded

    /// 登録済み識別子がUUIDとして解釈できません。終端の失敗です。
    case invalidIdentifier

    /// 自動再接続を止めた終端の理由かどうかです。
    ///
    /// 責務: 切断理由を「自動でやり直す」か「`stop()`→`start(preference:)` まで止まる」かへ分類します。
    var isTerminal: Bool {
        switch self {
        case .unknownUARTProfile, .retryLimitExceeded, .invalidIdentifier:
            true
        case .bluetoothPoweredOff, .bluetoothUnauthorized, .bluetoothUnsupported,
             .peripheralDisconnected, .connectionFailed, .discoveryFailed, .discoveryTimedOut:
            false
        }
    }
}
