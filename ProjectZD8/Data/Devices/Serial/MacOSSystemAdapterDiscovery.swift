#if os(macOS)
import CoreBluetooth
import Foundation
import IOKit
import IOKit.serial

/// macOSのIORegistryとBluetoothスタックからアダプター候補を取得します。
@MainActor
final class MacOSSystemAdapterDiscovery: NSObject, AdapterDiscoveryPort {
    /// Bluetooth Low Energyの一定時間スキャンを担当するオブジェクトです。
    private let bluetoothScanner: MacOSBluetoothLowEnergyScanner

    /// macOSのデバイス探索実装を生成します。
    ///
    /// 責務: Bluetoothスキャナーを保持するmacOSアダプター探索境界を構築します。
    override init() {
        bluetoothScanner = MacOSBluetoothLowEnergyScanner()
        super.init()
    }

    /// 指定された接続方式でmacOSから参照できる候補を取得します。
    ///
    /// 責務: 1種類の接続方式を対応するmacOSデバイス探索処理へ振り分けます。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: macOSのシステム情報から取得できた候補。
    /// - Throws: Bluetooth探索を開始できない場合の探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        switch mode {
        case .usb:
            return discoverUSBDevices()
        case .bluetooth:
            return try await bluetoothScanner.scan()
        }
    }

    /// IORegistryに現在登録されているUSBシリアルデバイスを候補へ変換します。
    ///
    /// 責務: 現在接続中でシリアル接続先として公開されたUSBデバイスを識別情報付きで列挙します。
    /// - Returns: IORegistryから読み取れたUSBシリアルデバイス候補。
    private func discoverUSBDevices() -> [DiscoveredAdapter] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOSerialBSDServiceValue),
            &iterator
        )
        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var adapters: [DiscoveredAdapter] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let adapter = makeUSBAdapter(from: service) {
                adapters.append(adapter)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return adapters
    }

    /// 1件のIORegistryシリアルエントリーを表示可能なUSB候補へ変換します。
    ///
    /// 責務: シリアル接続先とUSB祖先情報から1件のアダプター候補を構築します。
    /// - Parameter service: 読み取り対象のシリアルIORegistryエントリー。
    /// - Returns: USBシリアル接続先として確認できた候補。それ以外は `nil`。
    private func makeUSBAdapter(from service: io_registry_entry_t) -> DiscoveredAdapter? {
        guard let calloutDevice = stringProperty(kIOCalloutDeviceKey, from: service) else { return nil }
        let manufacturer = ancestorStringProperty("USB Vendor Name", startingAt: service)
        let product = ancestorStringProperty("USB Product Name", startingAt: service)
            ?? ancestorStringProperty("Product Name", startingAt: service)
        let serialNumber = ancestorStringProperty("USB Serial Number", startingAt: service)
        let vendorValue = ancestorNumberProperty("idVendor", startingAt: service)
        let productValue = ancestorNumberProperty("idProduct", startingAt: service)

        guard vendorValue != nil || calloutDevice.localizedCaseInsensitiveContains("usb") else {
            return nil
        }

        let vendorIdentifier = hexadecimalIdentifier(vendorValue, width: 4)
        let productIdentifier = hexadecimalIdentifier(productValue, width: 4)
        let systemIdentifier = calloutDevice
        let resolvedDisplayName = displayName(
            manufacturer: manufacturer,
            product: product,
            fallback: systemIdentifier
        )

        return DiscoveredAdapter(
            id: "usb:\(systemIdentifier)",
            transportMode: .usb,
            displayName: resolvedDisplayName,
            manufacturerName: manufacturer,
            productName: product,
            systemIdentifier: systemIdentifier,
            serialNumber: serialNumber,
            vendorIdentifier: vendorIdentifier,
            productIdentifier: productIdentifier,
            isConnected: true
        )
    }

    /// IORegistryエントリーから文字列プロパティを取得します。
    ///
    /// 責務: 1件のIORegistryプロパティを任意の文字列として読み取ります。
    /// - Parameters:
    ///   - key: 読み取るIORegistryプロパティ名。
    ///   - service: 読み取り対象のIORegistryエントリー。
    /// - Returns: 文字列として取得できた値。値がない場合は `nil`。
    private func stringProperty(_ key: String, from service: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// IORegistryエントリーと祖先から最初の文字列プロパティを取得します。
    ///
    /// 責務: シリアル接続先からUSBデバイスまでの祖先を辿って1件の文字列情報を見つけます。
    /// - Parameters:
    ///   - key: 読み取るIORegistryプロパティ名。
    ///   - service: 探索を開始するIORegistryエントリー。
    /// - Returns: 最初に取得できた文字列。祖先にも値がない場合は `nil`。
    private func ancestorStringProperty(_ key: String, startingAt service: io_registry_entry_t) -> String? {
        ancestorProperty(key, startingAt: service) as? String
    }

    /// IORegistryエントリーと祖先から最初の数値プロパティを取得します。
    ///
    /// 責務: シリアル接続先からUSBデバイスまでの祖先を辿って1件の数値情報を見つけます。
    /// - Parameters:
    ///   - key: 読み取るIORegistryプロパティ名。
    ///   - service: 探索を開始するIORegistryエントリー。
    /// - Returns: 最初に取得できた数値。祖先にも値がない場合は `nil`。
    private func ancestorNumberProperty(_ key: String, startingAt service: io_registry_entry_t) -> UInt64? {
        (ancestorProperty(key, startingAt: service) as? NSNumber)?.uint64Value
    }

    /// IORegistryエントリーの親階層から最初に見つかるプロパティを取得します。
    ///
    /// 責務: 指定された起点からIOService階層を限定段数だけ辿って1件のプロパティ値を返します。
    /// - Parameters:
    ///   - key: 読み取るIORegistryプロパティ名。
    ///   - service: 探索を開始するIORegistryエントリー。
    /// - Returns: 起点または祖先から取得できたCore Foundation値。存在しない場合は `nil`。
    private func ancestorProperty(_ key: String, startingAt service: io_registry_entry_t) -> Any? {
        var currentEntry = service
        var ownsCurrentEntry = false
        defer {
            if ownsCurrentEntry { IOObjectRelease(currentEntry) }
        }

        for _ in 0..<12 {
            if let value = IORegistryEntryCreateCFProperty(
                currentEntry,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() {
                return value
            }

            var parentEntry: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(currentEntry, kIOServicePlane, &parentEntry) == KERN_SUCCESS else {
                return nil
            }
            if ownsCurrentEntry { IOObjectRelease(currentEntry) }
            currentEntry = parentEntry
            ownsCurrentEntry = true
        }
        return nil
    }

    /// 数値をUSB識別子向けの固定幅16進表記へ変換します。
    ///
    /// 責務: 任意のUSB数値識別子を一貫した16進文字列へ整形します。
    /// - Parameters:
    ///   - value: 変換対象の数値。
    ///   - width: 先頭ゼロを含む最小桁数。
    /// - Returns: `0x` 接頭辞付きの16進文字列。値がない場合は `nil`。
    private func hexadecimalIdentifier(_ value: UInt64?, width: Int) -> String? {
        value.map { String(format: "0x%0*llX", width, $0) }
    }

    /// メーカー名と製品名から一覧表示名を決定します。
    ///
    /// 責務: システムから取得できた最も判別しやすい名称を1件の表示名へまとめます。
    /// - Parameters:
    ///   - manufacturer: システムから取得できたメーカー名称。
    ///   - product: システムから取得できた製品名称。
    ///   - fallback: 名称を取得できなかった場合の代替識別子。
    /// - Returns: 空白を除去した名称または代替識別子。
    private func displayName(manufacturer: String?, product: String?, fallback: String) -> String {
        let components = [manufacturer, product]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? fallback : components.joined(separator: " · ")
    }
}

/// CoreBluetoothで周辺のBluetooth Low Energyデバイスを一定時間探索します。
@MainActor
private final class MacOSBluetoothLowEnergyScanner: NSObject, CBCentralManagerDelegate {
    /// CoreBluetoothのスキャンと状態通知を提供する中央マネージャーです。
    private var centralManager: CBCentralManager?

    /// 現在のスキャンで検出した候補を識別子ごとに保持します。
    private var discoveredAdapters: [String: DiscoveredAdapter] = [:]

    /// Bluetooth Low Energyスキャナーを初期状態で生成します。
    ///
    /// 責務: CoreBluetoothスキャン開始前の空の探索状態を構築します。
    override init() {
        super.init()
    }

    /// 周辺のBluetooth Low Energyデバイスを一定時間探索します。
    ///
    /// 責務: CoreBluetoothで検出できた周辺機器を1回分の候補一覧として返します。
    /// - Returns: スキャン期間内に検出できたBluetooth Low Energy候補。
    /// - Throws: タスクがキャンセルされた場合の `CancellationError`。
    func scan() async throws -> [DiscoveredAdapter] {
        discoveredAdapters = [:]
        let manager = CBCentralManager(delegate: self, queue: .main)
        centralManager = manager

        for _ in 0..<15 where manager.state == .unknown || manager.state == .resetting {
            try await Task.sleep(for: .milliseconds(100))
        }

        guard manager.state == .poweredOn else {
            centralManager = nil
            throw MacOSAdapterDiscoveryError.bluetoothUnavailable
        }

        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            manager.stopScan()
            centralManager = nil
            throw error
        }
        manager.stopScan()
        centralManager = nil
        return Array(discoveredAdapters.values)
    }

    /// Bluetooth中央マネージャーの状態変更を受け取ります。
    ///
    /// 責務: CoreBluetoothが要求する中央マネージャー状態通知の受信境界を提供します。
    /// - Parameter central: 状態が変更された中央マネージャー。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    /// Bluetooth Low Energy周辺機器の検出情報を候補として記録します。
    ///
    /// 責務: 1件のCoreBluetooth検出通知を重複のないアダプター候補へ変換します。
    /// - Parameters:
    ///   - central: 検出通知を生成した中央マネージャー。
    ///   - peripheral: 検出されたBluetooth Low Energy周辺機器。
    ///   - advertisementData: 周辺機器が公開したアドバタイズ情報。
    ///   - RSSI: 検出時の受信信号強度。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let identifier = peripheral.identifier.uuidString
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let resolvedName = advertisedName ?? peripheral.name ?? identifier
        discoveredAdapters["bluetooth-low-energy:\(identifier)"] = DiscoveredAdapter(
            id: "bluetooth-low-energy:\(identifier)",
            transportMode: .bluetooth,
            displayName: resolvedName,
            productName: advertisedName ?? peripheral.name,
            systemIdentifier: identifier,
            isConnected: peripheral.state == .connected
        )
    }
}

/// macOSのデバイス探索を開始できない状態を表します。
private enum MacOSAdapterDiscoveryError: Error {
    /// Bluetoothが無効、未許可、またはこのMacで利用できません。
    case bluetoothUnavailable
}
#endif
