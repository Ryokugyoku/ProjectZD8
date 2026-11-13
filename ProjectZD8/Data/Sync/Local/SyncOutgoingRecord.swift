import Foundation

/// iCloudへ保存する1件のレコードの材料です。
nonisolated struct SyncOutgoingRecord: Equatable, Sendable {
    /// レコードの内容です。
    let payload: SyncRecordPayload
    /// 前回サーバーから受け取ったシステムフィールドです。新規なら `nil` です。
    let systemFields: Data?
    /// 写真の画像ファイルです。ファイルが無ければ `nil` です。
    let photoFileURL: URL?

    /// 責務: 保存するレコードの材料をまとめます。
    init(payload: SyncRecordPayload, systemFields: Data?, photoFileURL: URL? = nil) {
        self.payload = payload
        self.systemFields = systemFields
        self.photoFileURL = photoFileURL
    }
}
