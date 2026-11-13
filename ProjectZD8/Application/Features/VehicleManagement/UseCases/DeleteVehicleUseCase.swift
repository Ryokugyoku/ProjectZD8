import Foundation

/// 車両を、記録中でないことを確かめてから削除します。
nonisolated struct DeleteVehicleUseCase: Sendable {
    private let vehicles: any VehicleRepository
    private let sessions: any SessionRepository

    /// 責務: 削除に使う永続化契約を固定します。
    init(vehicles: any VehicleRepository, sessions: any SessionRepository) {
        self.vehicles = vehicles
        self.sessions = sessions
    }

    /// 車両と、その車両に属するデータを削除します。
    ///
    /// 責務: 記録中のセッションが無いことを確認して車両を削除します。
    /// - Parameter id: 削除する車両のID。
    /// - Throws: `VehicleManagementFailure.deleteRefusedWhileRecording` または `.deleteFailed`。
    func execute(_ id: VehicleID) async throws {
        do {
            guard try await sessions.sessions(for: id).allSatisfy({ !$0.isRecording }) else {
                throw VehicleManagementFailure.deleteRefusedWhileRecording
            }
            try await vehicles.delete(id)
        } catch let failure as VehicleManagementFailure {
            throw failure
        } catch {
            throw VehicleManagementFailure.deleteFailed
        }
    }
}
