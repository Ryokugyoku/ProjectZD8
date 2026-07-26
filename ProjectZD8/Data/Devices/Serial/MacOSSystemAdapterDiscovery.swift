#if os(macOS)
import Foundation
import IOBluetooth
import IOKit
import IOKit.serial

/// macOSのIORegistryとBluetooth Classicスタックからアダプター候補を取得します。
@MainActor
final class MacOSSystemAdapterDiscovery: NSObject, AdapterDiscoveryPort {
    /// OBDLink MX+に限定したBluetooth Classic探索を担当するオブジェクトです。
    private let bluetoothScanner: MacOSOBDLinkMXPlusBluetoothScanner

    /// macOSのデバイス探索実装を生成します。
    ///
    /// 責務: Bluetoothスキャナーを保持するmacOSアダプター探索境界を構築します。
    override init() {
        bluetoothScanner = MacOSOBDLinkMXPlusBluetoothScanner()
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
            return try await bluetoothScanner.discover()
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

/// Bluetooth Classicの履歴と周辺探索からOBDLink MX+だけを取得します。
@MainActor
private final class MacOSOBDLinkMXPlusBluetoothScanner: NSObject, IOBluetoothDeviceInquiryDelegate {
    /// OBDLink MX+名称とペアリング完了を検証する方針です。
    private let candidatePolicy = MacOSOBDLinkMXPlusDiscoveryPolicy()

    /// 現在実行中のBluetooth Classic探索です。
    private var inquiry: IOBluetoothDeviceInquiry?

    /// 現在の探索で検出したMX+候補をBluetoothアドレスごとに保持します。
    private var discoveredDevices: [String: IOBluetoothDevice] = [:]

    /// 現在の非同期探索を完了させる継続です。
    private var continuation: CheckedContinuation<[DiscoveredAdapter], any Error>?

    /// Bluetooth Classic探索に設ける終了タスクです。
    private var timeoutTask: Task<Void, Never>?

    /// Bluetooth Classicスキャナーを初期状態で生成します。
    ///
    /// 責務: OBDLink MX+探索開始前の空のBluetooth Classic状態を構築します。
    override init() {
        super.init()
    }

    /// 最近参照した機器と一定時間の周辺探索からOBDLink MX+候補を返します。
    ///
    /// 責務: macOSが既知または探索中に報告した機器をMX+専用候補一覧へ変換します。
    /// - Returns: 名称とペアリング状態を確認できたOBDLink MX+候補。
    /// - Throws: 探索開始失敗またはタスク取消し。
    func discover() async throws -> [DiscoveredAdapter] {
        try Task.checkCancellation()
        cancelActiveDiscovery()
        discoveredDevices = [:]
        addRecentOBDLinkDevices()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
                    finish(with: .failure(MacOSAdapterDiscoveryError.bluetoothUnavailable))
                    return
                }
                self.inquiry = inquiry
                guard inquiry.start() == kIOReturnSuccess else {
                    finish(with: .failure(MacOSAdapterDiscoveryError.bluetoothUnavailable))
                    return
                }
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.finish(with: .success(self?.makeAdapters() ?? []))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(with: .failure(CancellationError()))
            }
        }
    }

    /// Bluetooth Classic探索で1件見つかった機器をMX+候補として記録します。
    ///
    /// 責務: 1件のIOBluetooth探索通知を名称確認済みMX+辞書へ反映します。
    /// - Parameters:
    ///   - sender: 通知元のBluetooth探索。
    ///   - device: 見つかったBluetooth Classic機器。
    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!
    ) {
        addIfOBDLinkMXPlus(device)
    }

    /// Bluetooth Classic探索の完了結果を待機中の呼出元へ返します。
    ///
    /// 責務: 1回のIOBluetooth探索完了を候補一覧または利用不能エラーへ変換します。
    /// - Parameters:
    ///   - sender: 完了したBluetooth探索。
    ///   - error: IOBluetoothが返した探索結果。
    ///   - aborted: 呼出元または期限により中止されたかどうか。
    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!,
        error: IOReturn,
        aborted: Bool
    ) {
        guard error == kIOReturnSuccess || aborted else {
            finish(with: .failure(MacOSAdapterDiscoveryError.bluetoothUnavailable))
            return
        }
        finish(with: .success(makeAdapters()))
    }

    /// macOSの最近参照した機器からOBDLink MX+だけを現在候補へ追加します。
    ///
    /// 責務: 有限件数のBluetooth履歴を名称で保守的に絞り込み現在探索へ統合します。
    private func addRecentOBDLinkDevices() {
        let recentDevices = IOBluetoothDevice.recentDevices(32) as? [IOBluetoothDevice] ?? []
        recentDevices.forEach(addIfOBDLinkMXPlus)
    }

    /// 名称とBluetoothアドレスを持つOBDLink MX+を候補辞書へ追加します。
    ///
    /// 責務: 1件のBluetooth機器を公式MX+名称接頭辞で検証して重複なく保持します。
    /// - Parameter device: macOSが報告したBluetooth Classic機器。
    private func addIfOBDLinkMXPlus(_ device: IOBluetoothDevice) {
        guard let name = normalized(device.nameOrAddress),
              candidatePolicy.accepts(name: name, isPaired: device.isPaired()),
              let address = normalized(device.addressString) else {
            return
        }
        discoveredDevices[address] = device
    }

    /// 保持中のBluetooth機器を接続終端付きMX+候補へ変換します。
    ///
    /// 責務: 名称確認済みMX+辞書を安定順序のBluetooth Classic候補一覧へ写像します。
    /// - Returns: Bluetoothアドレス順に並べたMX+候補。
    private func makeAdapters() -> [DiscoveredAdapter] {
        discoveredDevices.compactMap { address, device in
            guard let name = normalized(device.nameOrAddress) else { return nil }
            return DiscoveredAdapter(
                id: "bluetooth-classic:\(address)",
                transportMode: .bluetooth,
                connectionTransport: .bluetoothClassic,
                displayName: name,
                manufacturerName: "OBD Solutions LLC",
                productName: "OBDLink MX+",
                systemIdentifier: address,
                isConnected: device.isConnected()
            )
        }
        .sorted { $0.systemIdentifier < $1.systemIdentifier }
    }

    /// 空白だけのBluetooth文字列を除外します。
    ///
    /// 責務: 1件の任意文字列を空でない前後空白除去済み値へ変換します。
    /// - Parameter value: macOSから取得した任意文字列。
    /// - Returns: 空でない正規化値。値がない場合は `nil`。
    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// 現在のBluetooth探索と期限タスクを破棄します。
    ///
    /// 責務: 以前の探索資源を次回探索へ持ち越さないよう停止します。
    private func cancelActiveDiscovery() {
        timeoutTask?.cancel()
        timeoutTask = nil
        inquiry?.stop()
        inquiry = nil
        continuation = nil
    }

    /// 現在のBluetooth探索を1回だけ完了します。
    ///
    /// 責務: 最初の探索結果だけで継続を再開してIOBluetooth資源を解放します。
    /// - Parameter result: 候補一覧または探索失敗。
    private func finish(with result: Result<[DiscoveredAdapter], any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        inquiry?.stop()
        inquiry = nil
        continuation.resume(with: result)
    }
}

/// macOSのBluetooth Classic探索を開始できない状態を表します。
private enum MacOSAdapterDiscoveryError: Error {
    /// Bluetoothが無効、未許可、またはこのMacで利用できません。
    case bluetoothUnavailable
}
#endif
