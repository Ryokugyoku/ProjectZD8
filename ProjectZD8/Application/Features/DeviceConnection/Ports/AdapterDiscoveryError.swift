/// アダプター探索を実行できない理由をApplication境界で表します。
enum AdapterDiscoveryError: Error, Equatable {
    /// 実行環境が要求された接続方式を製品機能として提供していません。
    case transportUnsupported

    /// Bluetoothがシステム設定で無効です。
    case bluetoothPoweredOff

    /// Bluetooth利用が許可されていません。
    case bluetoothUnauthorized

    /// 実行環境がBluetooth Low Energy中央デバイス機能に対応していません。
    case bluetoothUnsupported

    /// Bluetoothの準備状態を期限内に確定できませんでした。
    case bluetoothStateUnavailable
}
