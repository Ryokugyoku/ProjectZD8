/// 物理通信を行わない製品内デモOBDアダプターを定義します。
enum DemoOBDAdapter {
    /// デモUSB終端を識別する予約済みシステム識別子です。
    static let usbSystemIdentifier = "projectzd8://demo-usb"
    /// デモBluetooth終端を識別する予約済みシステム識別子です。
    static let bluetoothSystemIdentifier = "projectzd8://demo-bluetooth"

    /// USB探索結果へ常時追加するデモ候補です。
    static let candidate = DiscoveredAdapter(
        id: "usb:projectzd8-demo",
        transportMode: .usb,
        displayName: "DEMO USB",
        manufacturerName: "ProjectZD8",
        productName: "Demo OBD Adapter",
        systemIdentifier: usbSystemIdentifier,
        serialNumber: "ZD8-DEMO-0001",
        vendorIdentifier: "DEMO",
        productIdentifier: "USB",
        isConnected: true
    )

    /// Bluetooth探索結果へ常時追加するiOS向けデモ候補です。
    static let bluetoothCandidate = DiscoveredAdapter(
        id: "bluetooth-low-energy:projectzd8-demo",
        transportMode: .bluetooth,
        displayName: "DEMO Bluetooth",
        manufacturerName: "ProjectZD8",
        productName: "Demo BLE OBD Adapter",
        advertisementLocalName: "DEMO Bluetooth",
        hasManufacturerData: false,
        systemIdentifier: bluetoothSystemIdentifier,
        serialNumber: "ZD8-DEMO-BLE-0001",
        isConnected: true
    )

    /// 指定終端が製品内デモ通信を表すか判定します。
    ///
    /// 責務: 1件のOBD終端を予約済みデモ識別子と照合します。
    /// - Parameter endpoint: 判定するOBD接続終端。
    /// - Returns: デモ終端と一致する場合は `true`。
    static func matches(_ endpoint: OBDConnectionEndpoint) -> Bool {
        [usbSystemIdentifier, bluetoothSystemIdentifier].contains(endpoint.systemIdentifier)
    }
}
