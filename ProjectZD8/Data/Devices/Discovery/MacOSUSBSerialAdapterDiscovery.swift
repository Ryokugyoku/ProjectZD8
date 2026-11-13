#if os(macOS)
import Foundation
import IOKit
import IOKit.serial

/// IORegistryに登録されたUSBシリアルデバイスをアダプター候補として取得します。
nonisolated struct MacOSUSBSerialAdapterDiscovery: AdapterDiscoveryPort {
    /// 探索実装を生成します。
    ///
    /// 責務: 状態を持たないUSBシリアル探索境界を構築します。
    init() {}

    /// 責務: 現在接続中でシリアル接続先として公開されたUSBデバイスを列挙します。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOSerialBSDServiceValue),
            &iterator
        )
        guard result == KERN_SUCCESS else { throw AdapterDiscoveryError.failed }
        defer { IOObjectRelease(iterator) }

        var adapters: [AdapterDescriptor] = []
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

    /// 責務: シリアル接続先とUSB祖先情報から1件のアダプター候補を構築します。
    private func makeUSBAdapter(from service: io_registry_entry_t) -> AdapterDescriptor? {
        guard let calloutDevice = stringProperty(kIOCalloutDeviceKey, from: service) else { return nil }
        let manufacturer = ancestorStringProperty("USB Vendor Name", startingAt: service)
        let product = ancestorStringProperty("USB Product Name", startingAt: service)
            ?? ancestorStringProperty("Product Name", startingAt: service)
        let vendorValue = ancestorNumberProperty("idVendor", startingAt: service)

        guard vendorValue != nil || calloutDevice.localizedCaseInsensitiveContains("usb") else {
            return nil
        }
        let displayName = Self.displayName(manufacturer: manufacturer, product: product, fallback: calloutDevice)
        return AdapterDescriptor(
            transport: .usbSerial,
            systemIdentifier: calloutDevice,
            displayName: displayName,
            detail: calloutDevice == displayName ? nil : calloutDevice
        )
    }

    /// 責務: IORegistryエントリーから文字列プロパティを任意値として読み取ります。
    private func stringProperty(_ key: String, from service: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// 責務: シリアル接続先からUSBデバイスまでの祖先を辿って文字列情報を1件見つけます。
    private func ancestorStringProperty(_ key: String, startingAt service: io_registry_entry_t) -> String? {
        ancestorProperty(key, startingAt: service) as? String
    }

    /// 責務: シリアル接続先からUSBデバイスまでの祖先を辿って数値情報を1件見つけます。
    private func ancestorNumberProperty(_ key: String, startingAt service: io_registry_entry_t) -> UInt64? {
        (ancestorProperty(key, startingAt: service) as? NSNumber)?.uint64Value
    }

    /// 責務: 指定された起点からIOService階層を限定段数だけ辿って最初のプロパティ値を返します。
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

    /// 責務: メーカー名と製品名から一覧表示名を決めます。どちらも無ければ代替識別子を返します。
    static func displayName(manufacturer: String?, product: String?, fallback: String) -> String {
        let components = [manufacturer, product]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? fallback : components.joined(separator: " · ")
    }
}
#endif
