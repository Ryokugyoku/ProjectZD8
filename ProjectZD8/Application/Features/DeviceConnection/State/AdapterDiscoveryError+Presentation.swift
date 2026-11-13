extension AdapterDiscoveryError {
    /// 画面表示用のローカライズキーです。
    nonisolated var localizationKey: String {
        switch self {
        case .bluetoothPoweredOff: "device.discovery.failure.bluetoothPoweredOff"
        case .bluetoothUnauthorized: "device.discovery.failure.bluetoothUnauthorized"
        case .bluetoothUnsupported: "device.discovery.failure.bluetoothUnsupported"
        case .failed: "device.discovery.failure.failed"
        }
    }
}
