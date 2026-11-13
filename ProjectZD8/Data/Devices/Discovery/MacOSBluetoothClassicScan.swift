#if os(macOS)
import Foundation
import IOBluetooth

/// 1回分のBluetooth Classic探索を担当する使い捨てのセッションです。
@MainActor
final class MacOSBluetoothClassicScan: NSObject, IOBluetoothDeviceInquiryDelegate {
    /// OBDLink MX+名称とペアリング完了を検証する方針です。
    private let candidatePolicy = MacOSOBDLinkMXPlusDiscoveryPolicy()

    /// 現在実行中のBluetooth Classic探索です。
    private var inquiry: IOBluetoothDeviceInquiry?

    /// 検出したMX+候補をBluetoothアドレスごとに保持します。
    private var discoveredDevices: [String: IOBluetoothDevice] = [:]

    /// 非同期探索を完了させる継続です。
    private var continuation: CheckedContinuation<[AdapterDescriptor], any Error>?

    /// 探索に設ける終了タスクです。
    private var timeoutTask: Task<Void, Never>?

    /// 責務: macOSが既知または探索中に報告した機器をMX+専用候補一覧へ変換します。
    /// - Throws: 探索開始失敗(`AdapterDiscoveryError.failed`)またはタスク取消し。
    func run() async throws -> [AdapterDescriptor] {
        try Task.checkCancellation()
        addRecentOBDLinkDevices()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
                    finish(with: .failure(AdapterDiscoveryError.failed))
                    return
                }
                self.inquiry = inquiry
                guard inquiry.start() == kIOReturnSuccess else {
                    finish(with: .failure(AdapterDiscoveryError.failed))
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

    /// 責務: 1件の探索通知を名称確認済みMX+辞書へ反映します。
    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!
    ) {
        addIfOBDLinkMXPlus(device)
    }

    /// 責務: 探索完了を候補一覧または失敗へ変換して待機中の呼び出しへ返します。
    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!,
        error: IOReturn,
        aborted: Bool
    ) {
        guard error == kIOReturnSuccess || aborted else {
            finish(with: .failure(AdapterDiscoveryError.failed))
            return
        }
        finish(with: .success(makeAdapters()))
    }

    /// 責務: macOSの最近参照した機器(最大32件)からMX+だけを候補へ追加します。
    private func addRecentOBDLinkDevices() {
        let recentDevices = IOBluetoothDevice.recentDevices(32) as? [IOBluetoothDevice] ?? []
        recentDevices.forEach(addIfOBDLinkMXPlus)
    }

    /// 責務: 1件のBluetooth機器を公式MX+名称とペアリング状態で検証して保持します。
    private func addIfOBDLinkMXPlus(_ device: IOBluetoothDevice) {
        guard let name = normalized(device.nameOrAddress),
              candidatePolicy.accepts(name: name, isPaired: device.isPaired()),
              let address = normalized(device.addressString) else {
            return
        }
        discoveredDevices[address] = device
    }

    /// 責務: 保持中のMX+機器をBluetoothアドレス順のClassic候補へ写像します。
    private func makeAdapters() -> [AdapterDescriptor] {
        discoveredDevices.compactMap { address, device in
            guard let name = normalized(device.nameOrAddress) else { return nil }
            return AdapterDescriptor(
                transport: .bluetoothClassic,
                systemIdentifier: address,
                displayName: name,
                detail: "OBDLink MX+"
            )
        }
        .sorted { $0.systemIdentifier < $1.systemIdentifier }
    }

    /// 責務: 空白だけの文字列を欠損として扱います。
    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// 責務: 探索と期限タスクを止め、待機中の呼び出しへ結果を1回だけ返します。
    private func finish(with result: Result<[AdapterDescriptor], any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        inquiry?.stop()
        inquiry = nil
        continuation.resume(with: result)
    }
}
#endif
