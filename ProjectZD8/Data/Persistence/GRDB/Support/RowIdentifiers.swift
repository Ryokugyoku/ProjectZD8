import Foundation

/// ID値オブジェクトとデータベースのID列(小文字UUID文字列)の相互変換です。
nonisolated protocol RowIdentifiable {
    /// UUIDの値です。
    var rawValue: UUID { get }
    /// 責務: UUIDからIDを生成します。
    init(rawValue: UUID)
}

nonisolated extension VehicleID: RowIdentifiable {}
nonisolated extension SessionID: RowIdentifiable {}
nonisolated extension MaintenanceRecordID: RowIdentifiable {}
nonisolated extension PhotoID: RowIdentifiable {}

nonisolated extension RowIdentifiable {
    /// データベースのID列へ保存する小文字UUID文字列です。
    var rowID: String { rawValue.uuidString.lowercased() }

    /// 責務: ID列の文字列からIDを復元します。UUIDとして不正なら `StoreError.ioFailure` を投げます。
    init(rowID: String) throws {
        guard let uuid = UUID(uuidString: rowID) else { throw StoreError.ioFailure }
        self.init(rawValue: uuid)
    }
}
