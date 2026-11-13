import Foundation
import GRDB

/// 車両写真をGRDB(メタデータ)とファイル(画像本体)で永続化します。
nonisolated struct GRDBPhotoRepository: PhotoRepository {
    private let database: AppDatabase
    private let files: PhotoFileStore
    private let now: @Sendable () -> Date

    /// 責務: 共有データベースと写真ファイルストアを使うリポジトリを生成します。
    init(database: AppDatabase, files: PhotoFileStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.files = files
        self.now = now
    }

    /// 責務: 画像をJPEG(長辺2048px以下・品質0.8)へ正規化して保存し、新しい写真IDを返します。画像として解釈できなければ `StoreError.ioFailure` を投げます。
    func save(_ imageData: Data, for vehicleID: VehicleID) async throws -> PhotoID {
        let jpeg = try PhotoImageNormalizer.normalizedJPEG(from: imageData)
        let id = PhotoID()
        let timestamp = now().epochMilliseconds
        let record = PhotoRecord(
            id: id.rowID, vehicleID: vehicleID.rowID, byteCount: jpeg.count,
            createdAt: timestamp, modifiedAt: timestamp, deletedAt: nil
        )
        do {
            try files.write(jpeg, for: id)
        } catch {
            throw StoreError.ioFailure
        }
        do {
            try await database.storeWrite { db in
                guard try VehicleRecord.filter(Column("id") == record.vehicleID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                    throw StoreError.notFound
                }
                try record.insert(db)
            }
        } catch {
            try? files.remove(id)
            throw error
        }
        return id
    }

    /// 責務: 削除されていない写真の画像データを返します。行またはファイルが無ければ `nil` を返します。
    func imageData(for id: PhotoID) async throws -> Data? {
        let rowID = id.rowID
        let exists = try await database.storeRead { db in
            try PhotoRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchCount(db) == 1
        }
        guard exists else { return nil }
        do {
            return try files.read(id)
        } catch {
            throw StoreError.ioFailure
        }
    }

    /// 責務: 写真を削除します。同期済みなら行を墓標化し、画像ファイルはどちらの場合もこの端末から削除します。
    func delete(_ id: PhotoID) async throws {
        let rowID = id.rowID
        let timestamp = now()
        try await database.storeWrite { db in
            guard try PhotoRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            try PhotoRowDeletion.remove([rowID], now: timestamp, in: db)
        }
        do {
            try files.remove(id)
        } catch {
            throw StoreError.ioFailure
        }
    }
}
