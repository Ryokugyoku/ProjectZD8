import Foundation
@testable import ProjectZD8

/// 呼び出しを順序付きで記録し、イベントをテストから明示的に流すBluetooth中央役のフェイクです。
@MainActor
final class BLECentralRoleFake: BLECentralRole {
    /// 中央役へ届いた1件の呼び出しです。ペリフェラルは識別子で記録します。
    enum Call: Equatable {
        /// 識別子からの取得です。
        case retrievePeripherals([UUID])
        /// Service限定スキャンの開始です。
        case scanForPeripherals([String])
        /// スキャンの停止です。
        case stopScan
        /// 接続要求です。
        case connect(UUID)
        /// 接続キャンセルです。
        case cancelConnection(UUID)
    }

    /// 現在の電源・利用可否状態です。`setPowerState(_:)` で変更します。
    private(set) var powerState: BLECentralPowerState
    /// リンクが設定する中央役イベントの通知先です。
    var eventHandler: (@MainActor (BLECentralEvent) -> Void)?
    /// `retrievePeripherals(withIdentifiers:)` が返す一覧です。
    var retrieveResult: [any BLEPeripheralRole] = []
    /// 呼び出し順の記録です。
    private(set) var calls: [Call] = []

    /// 初期の電源状態を固定して生成します。
    ///
    /// 責務: 1件のシナリオの開始時の電源状態を保持します。
    /// - Parameter powerState: 初期の電源状態。
    init(powerState: BLECentralPowerState) {
        self.powerState = powerState
    }

    /// 接続要求の回数です。
    var connectCallCount: Int {
        calls.filter { if case .connect = $0 { true } else { false } }.count
    }

    /// 電源状態を変更して更新イベントを流します。
    ///
    /// 責務: 電源状態を置き換え、同じ値の更新イベントを通知先へ同期的に渡します。
    /// - Parameter newState: 新しい電源状態。
    func setPowerState(_ newState: BLECentralPowerState) {
        powerState = newState
        emit(.powerStateDidUpdate(newState))
    }

    /// 中央役イベントを通知先へ同期的に流します。
    ///
    /// 責務: テストが指定した1件のイベントをそのまま通知先へ渡します。
    /// - Parameter event: 流すイベント。
    func emit(_ event: BLECentralEvent) {
        eventHandler?(event)
    }

    /// 取得呼び出しを記録して固定の一覧を返します。
    ///
    /// 責務: 呼び出しを記録し、`retrieveResult` をそのまま返します。
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [any BLEPeripheralRole] {
        calls.append(.retrievePeripherals(identifiers))
        return retrieveResult
    }

    /// スキャン開始を記録します。
    ///
    /// 責務: 指定Service UUIDとともに呼び出しを記録します。
    func scanForPeripherals(withServices serviceUUIDs: [String]) {
        calls.append(.scanForPeripherals(serviceUUIDs))
    }

    /// スキャン停止を記録します。
    ///
    /// 責務: 呼び出しを記録します。
    func stopScan() {
        calls.append(.stopScan)
    }

    /// 接続要求を記録します。
    ///
    /// 責務: 対象の識別子とともに呼び出しを記録します。
    func connect(_ peripheral: any BLEPeripheralRole) {
        calls.append(.connect(peripheral.identifier))
    }

    /// 接続キャンセルを記録します。
    ///
    /// 責務: 対象の識別子とともに呼び出しを記録します。
    func cancelConnection(_ peripheral: any BLEPeripheralRole) {
        calls.append(.cancelConnection(peripheral.identifier))
    }
}
