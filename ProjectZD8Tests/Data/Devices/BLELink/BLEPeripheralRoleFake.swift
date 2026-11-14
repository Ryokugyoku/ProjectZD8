import Foundation
@testable import ProjectZD8

/// 呼び出しを順序付きで記録し、イベントをテストから明示的に流すペリフェラル役のフェイクです。
@MainActor
final class BLEPeripheralRoleFake: BLEPeripheralRole {
    /// ペリフェラルへ届いた1件の呼び出しです。
    enum Call: Equatable {
        /// Service探索の要求です。
        case discoverServices([String]?)
        /// Characteristic探索の要求です。
        case discoverCharacteristics(String)
        /// Notify状態変更の要求です。
        case setNotifyValue(Bool, characteristicUUID: String, serviceUUID: String)
        /// 1チャンクの書き込みです。
        case writeValue(Data, characteristicUUID: String, serviceUUID: String, kind: BLEWriteKind)
    }

    /// OSが割り当てた識別子です。
    let identifier: UUID
    /// 現在の接続状態です。
    var connectionState: BLEPeripheralConnectionState
    /// 応答なし書き込みを送れる残り回数です。`nil` は無制限で、書き込むたびに1減ります。
    var withoutResponseSendCredits: Int?
    /// 書き込み種別ごとの最大書き込み長です。
    var maximumWriteLengths: [BLEWriteKind: Int] = [.withResponse: 20, .withoutResponse: 20]
    /// リンクが設定するペリフェラル役イベントの通知先です。
    var eventHandler: (@MainActor (BLEPeripheralEvent) -> Void)?
    /// 呼び出し順の記録です。
    private(set) var calls: [Call] = []

    /// 識別子と接続状態を固定して生成します。
    ///
    /// 責務: 1件のシナリオのペリフェラル識別子と接続状態を保持します。
    /// - Parameters:
    ///   - identifier: ペリフェラル識別子。
    ///   - connectionState: 初期の接続状態。
    init(identifier: UUID, connectionState: BLEPeripheralConnectionState = .disconnected) {
        self.identifier = identifier
        self.connectionState = connectionState
    }

    /// 応答なし書き込みを今すぐ送れるかどうかです。
    var canSendWriteWithoutResponse: Bool {
        withoutResponseSendCredits.map { $0 > 0 } ?? true
    }

    /// 書き込まれた呼び出しだけを順に返します。
    var writeCalls: [Call] {
        calls.filter { if case .writeValue = $0 { true } else { false } }
    }

    /// 書き込まれたチャンクを順に返します。
    var writtenChunks: [Data] {
        calls.compactMap { if case .writeValue(let data, _, _, _) = $0 { data } else { nil } }
    }

    /// ペリフェラル役イベントを通知先へ同期的に流します。
    ///
    /// 責務: テストが指定した1件のイベントをそのまま通知先へ渡します。
    /// - Parameter event: 流すイベント。
    func emit(_ event: BLEPeripheralEvent) {
        eventHandler?(event)
    }

    /// Service探索を記録します。
    ///
    /// 責務: 指定Serviceとともに呼び出しを記録します。
    func discoverServices(_ serviceUUIDs: [String]?) {
        calls.append(.discoverServices(serviceUUIDs))
    }

    /// Characteristic探索を記録します。
    ///
    /// 責務: 対象Serviceとともに呼び出しを記録します。
    func discoverCharacteristics(forService serviceUUID: String) {
        calls.append(.discoverCharacteristics(serviceUUID))
    }

    /// Notify状態変更を記録します。
    ///
    /// 責務: 対象Characteristicとともに呼び出しを記録します。
    func setNotifyValue(_ enabled: Bool, characteristicUUID: String, serviceUUID: String) {
        calls.append(.setNotifyValue(enabled, characteristicUUID: characteristicUUID, serviceUUID: serviceUUID))
    }

    /// 種別ごとの固定の最大書き込み長を返します。
    ///
    /// 責務: `maximumWriteLengths` の値を返し、未設定なら0を返します。
    func maximumWriteValueLength(for kind: BLEWriteKind) -> Int {
        maximumWriteLengths[kind] ?? 0
    }

    /// 1チャンクの書き込みを記録し、応答なしなら送信可能回数を1減らします。
    ///
    /// 責務: 書き込み内容を記録し、OSの送信バッファ消費を模します。
    func writeValue(_ data: Data, characteristicUUID: String, serviceUUID: String, kind: BLEWriteKind) {
        calls.append(.writeValue(data, characteristicUUID: characteristicUUID, serviceUUID: serviceUUID, kind: kind))
        if kind == .withoutResponse, let credits = withoutResponseSendCredits {
            withoutResponseSendCredits = credits - 1
        }
    }
}
