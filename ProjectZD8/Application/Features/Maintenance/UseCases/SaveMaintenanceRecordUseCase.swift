import Foundation

/// 整備記録の入力を保存し、記録から外れた写真を片付けます。
nonisolated struct SaveMaintenanceRecordUseCase: Sendable {
    private let maintenance: any MaintenanceRepository
    private let photos: any PhotoRepository

    /// 責務: 保存に使う永続化契約を固定します。
    init(maintenance: any MaintenanceRepository, photos: any PhotoRepository) {
        self.maintenance = maintenance
        self.photos = photos
    }

    /// 入力を検証して保存します。
    ///
    /// 責務: 入力を更新日時付きの記録として保存し、編集前にあって記録から外れた写真を削除します。
    /// - Parameters:
    ///   - draft: 保存する入力。
    ///   - originalPhotoIDs: 編集開始時点で記録に含まれていた写真ID。
    ///   - now: 更新日時。
    /// - Returns: 保存した記録と、外れた写真を削除できたかどうか。
    /// - Throws: `MaintenanceFailure.invalidInput` または `.saveFailed`。
    func execute(draft: MaintenanceDraft, originalPhotoIDs: Set<PhotoID>, now: Date) async throws -> (record: MaintenanceRecord, didFailToDeletePhotos: Bool) {
        guard draft.issues().isEmpty else { throw MaintenanceFailure.invalidInput }
        let record = draft.makeRecord(modifiedAt: now)
        do {
            try await maintenance.save(record)
        } catch {
            throw MaintenanceFailure.saveFailed
        }
        let keptIDs = Set(record.photos.map(\.id))
        var didFail = false
        for removed in originalPhotoIDs.subtracting(keptIDs) {
            do { try await photos.delete(removed) } catch { didFail = true }
        }
        return (record, didFail)
    }
}
