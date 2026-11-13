import Foundation

/// 親の車両より先に届いたため保留している子レコードです。`sync_state` に保存し、再起動後も保持します。
nonisolated struct SyncParkedRecord: Codable, Equatable, Sendable {
    /// レコードの内容です。
    let payload: SyncRecordPayload
    /// サーバーから受け取ったシステムフィールドです。
    let systemFields: Data

    /// 責務: 保留する子レコードをまとめます。
    init(payload: SyncRecordPayload, systemFields: Data) {
        self.payload = payload
        self.systemFields = systemFields
    }

    /// `sync_state` に保存する時のキーの接頭辞です。
    static let keyPrefix = "parked."

    /// 責務: 保存キーを返します。
    static func key(recordType: SyncRecordType, recordName: String) -> String {
        "\(keyPrefix)\(recordType.rawValue).\(recordName)"
    }
}
