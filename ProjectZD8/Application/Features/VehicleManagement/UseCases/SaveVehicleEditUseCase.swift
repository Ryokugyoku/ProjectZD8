import Foundation

/// 車両の編集入力を保存し、不要になった写真を片付けます。
nonisolated struct SaveVehicleEditUseCase: Sendable {
    /// 保存結果です。
    struct Result: Equatable, Sendable {
        /// 保存した車両です。
        let vehicle: Vehicle
        /// 置き換えられた古い写真を削除できなかったかどうかです。
        let didFailToDeleteReplacedPhoto: Bool
    }

    private let vehicles: any VehicleRepository
    private let photos: any PhotoRepository

    /// 責務: 保存に使う永続化契約を固定します。
    init(vehicles: any VehicleRepository, photos: any PhotoRepository) {
        self.vehicles = vehicles
        self.photos = photos
    }

    /// 編集入力を検証して保存します。
    ///
    /// 責務: 入力を保存済みの車両へ反映して保存し、置き換えられた元の写真を削除します。
    /// - Parameters:
    ///   - draft: 保存する入力。
    ///   - originalPhotoID: 編集開始時点の写真ID。
    ///   - now: 更新日時。
    ///   - currentYear: 年式検証に使う西暦。
    /// - Throws: `VehicleManagementFailure.invalidInput` / `.vehicleNotFound` / `.saveFailed`。
    func execute(draft: VehicleEditDraft, originalPhotoID: PhotoID?, now: Date, currentYear: Int) async throws -> Result {
        guard draft.issues(currentYear: currentYear).isEmpty else { throw VehicleManagementFailure.invalidInput }
        let updated: Vehicle
        do {
            guard let stored = try await vehicles.vehicle(draft.vehicleID) else { throw VehicleManagementFailure.vehicleNotFound }
            updated = draft.applied(to: stored, modifiedAt: now)
            try await vehicles.save(updated)
        } catch let failure as VehicleManagementFailure {
            throw failure
        } catch {
            throw VehicleManagementFailure.saveFailed
        }
        var didFail = false
        if let originalPhotoID, originalPhotoID != draft.photoID {
            do { try await photos.delete(originalPhotoID) } catch { didFail = true }
        }
        return Result(vehicle: updated, didFailToDeleteReplacedPhoto: didFail)
    }
}
