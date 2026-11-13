/// OBDアダプターとの通信経路です。
nonisolated enum AdapterTransport: String, Codable, CaseIterable, Sendable {
    /// Bluetooth Low Energy のUARTサービス。
    case bluetoothLowEnergy
    /// Bluetooth Classic(macOSはRFCOMM、iOSはExternalAccessory)。
    case bluetoothClassic
    /// USBシリアル(macOSのみ)。
    case usbSerial
    /// デモモード用の模擬アダプター。実車データとして扱いません。
    case demo
}
