import Foundation

/// 物理通信を行わない製品内デモOBDアダプターを定義します。
enum DemoOBDAdapter {
    /// デモUSB終端を識別する予約済みシステム識別子一覧です。
    private static let usbSystemIdentifiers = [
        "projectzd8://demo-usb",
        "projectzd8://demo-usb-2",
        "projectzd8://demo-usb-3"
    ]
    /// デモBluetooth終端を識別する予約済みシステム識別子一覧です。
    private static let bluetoothSystemIdentifiers = [
        "projectzd8://demo-bluetooth",
        "projectzd8://demo-bluetooth-2",
        "projectzd8://demo-bluetooth-3"
    ]

    /// USB探索結果へ常時追加する3件のデモ候補です。
    static let usbCandidates = usbSystemIdentifiers.enumerated().map { index, systemIdentifier in
        DiscoveredAdapter(
            id: index == 0 ? "usb:projectzd8-demo" : "usb:projectzd8-demo-\(index + 1)",
            transportMode: .usb,
            displayName: index == 0 ? "DEMO USB" : "DEMO USB \(index + 1)",
            manufacturerName: "ProjectZD8",
            productName: "Demo OBD Adapter",
            systemIdentifier: systemIdentifier,
            serialNumber: String(format: "ZD8-DEMO-%04d", index + 1),
            vendorIdentifier: "DEMO",
            productIdentifier: "USB",
            isConnected: true
        )
    }

    /// Bluetooth探索結果へ常時追加する3件のiOS向けデモ候補です。
    static let bluetoothCandidates = bluetoothSystemIdentifiers.enumerated().map { index, systemIdentifier in
        DiscoveredAdapter(
            id: index == 0
                ? "bluetooth-low-energy:projectzd8-demo"
                : "bluetooth-low-energy:projectzd8-demo-\(index + 1)",
            transportMode: .bluetooth,
            displayName: index == 0 ? "DEMO Bluetooth" : "DEMO Bluetooth \(index + 1)",
            manufacturerName: "ProjectZD8",
            productName: "Demo BLE OBD Adapter",
            advertisementLocalName: index == 0 ? "DEMO Bluetooth" : "DEMO Bluetooth \(index + 1)",
            hasManufacturerData: false,
            systemIdentifier: systemIdentifier,
            serialNumber: String(format: "ZD8-DEMO-BLE-%04d", index + 1),
            isConnected: true
        )
    }

    /// 既存参照との互換性を保つ先頭USBデモ候補です。
    static let candidate = usbCandidates[0]

    /// 既存参照との互換性を保つ先頭Bluetoothデモ候補です。
    static let bluetoothCandidate = bluetoothCandidates[0]

    /// 指定終端が製品内デモ通信を表すか判定します。
    ///
    /// 責務: 1件のOBD終端を予約済みデモ識別子と照合します。
    /// - Parameter endpoint: 判定するOBD接続終端。
    /// - Returns: デモ終端と一致する場合は `true`。
    static func matches(_ endpoint: OBDConnectionEndpoint) -> Bool {
        (usbSystemIdentifiers + bluetoothSystemIdentifiers).contains(endpoint.systemIdentifier)
    }

    /// デモ終端から再現可能な合成VINを生成します。
    ///
    /// 責務: 1件のデモ終端を重複しない固定VINへ変換します。
    /// - Parameter endpoint: 合成VINを採番するデモ終端。
    /// - Returns: 17文字のデモVIN。
    static func syntheticVIN(for endpoint: OBDConnectionEndpoint) -> String {
        guard let index = enumeratedPrefixIndex(for: endpoint) else {
            return "TESTZD8CXR0000000"
        }
        return "TESTZD8CXR" + String(format: "%07d", index)
    }

    /// 1件のデモ終端を17文字VINの連番へ収束します。
    ///
    /// 責務: 1件のデモ候補をシステム識別子順の固定番号へ変換します。
    /// - Parameter endpoint: 変換対象のOBD終端。
    /// - Returns: 1から6までのシリアル番号。見つからない場合は `nil`。
    private static func enumeratedPrefixIndex(for endpoint: OBDConnectionEndpoint) -> Int? {
        let allIdentifiers = usbSystemIdentifiers + bluetoothSystemIdentifiers
        guard let index = allIdentifiers.firstIndex(of: endpoint.systemIdentifier) else {
            return nil
        }
        return index + 1
    }
}
