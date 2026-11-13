import Foundation

/// `maintenance_records.detail` に保存するJSONの内容です。
nonisolated struct MaintenanceRecordDetail: Codable, Sendable {
    var workItems: [MaintenanceWorkItem]
    var photos: [MaintenancePhoto]
    var fastenerGroups: [MaintenanceFastenerGroup]

    /// 責務: 整備記録から詳細部分を取り出します。
    init(_ record: MaintenanceRecord) {
        workItems = record.workItems
        photos = record.photos
        fastenerGroups = record.fastenerGroups
    }

    /// 責務: JSONへ変換します。日時はミリ秒で保存します。
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// 責務: JSONから復元します。復元できなければ `StoreError.ioFailure` を投げます。
    static func decode(_ data: Data) throws -> MaintenanceRecordDetail {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(MaintenanceRecordDetail.self, from: data)
        } catch {
            throw StoreError.ioFailure
        }
    }

    /// 責務: この記録が参照する全写真IDを返します(写真・締結の分解/組立写真を含む)。
    var referencedPhotoIDs: Set<PhotoID> {
        var ids = Set(photos.map(\.id))
        for group in fastenerGroups {
            ids.formUnion(group.removalPhotoIDs)
            for installation in group.installations { ids.formUnion(installation.photoIDs) }
        }
        return ids
    }
}
