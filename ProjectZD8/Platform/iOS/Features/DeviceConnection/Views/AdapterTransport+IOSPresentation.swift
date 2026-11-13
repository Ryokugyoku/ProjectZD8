#if os(iOS)
/// 通信経路の iOS 向け表示(アイコンと名称キー)です。
extension AdapterTransport {
    /// 経路を示す SF Symbol 名です。
    var iosSymbolName: String {
        switch self {
        case .bluetoothLowEnergy: "dot.radiowaves.left.and.right"
        case .bluetoothClassic: "wave.3.right"
        case .usbSerial: "cable.connector"
        case .demo: "testtube.2"
        }
    }

    /// 経路の表示名のローカライズキーです。
    var iosNameKey: String { "device.transport.\(rawValue)" }
}
#endif
