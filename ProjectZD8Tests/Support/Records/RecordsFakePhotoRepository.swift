import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `PhotoRepository` です。
final class RecordsFakePhotoRepository: PhotoRepository, Sendable {
    private let state: Mutex<State>

    private struct State {
        var images: [PhotoID: Data]
        var deleted: [PhotoID] = []
        var saveError: StoreError?
        var deleteError: StoreError?
        var readError: StoreError?
    }

    init(images: [PhotoID: Data] = [:]) {
        state = Mutex(State(images: images))
    }

    var storedIDs: Set<PhotoID> { state.withLock { Set($0.images.keys) } }
    var deletedIDs: [PhotoID] { state.withLock { $0.deleted } }
    func setSaveError(_ error: StoreError?) { state.withLock { $0.saveError = error } }
    func setDeleteError(_ error: StoreError?) { state.withLock { $0.deleteError = error } }
    func setReadError(_ error: StoreError?) { state.withLock { $0.readError = error } }

    func save(_ imageData: Data, for vehicleID: VehicleID) async throws -> PhotoID {
        try state.withLock { s in
            if let error = s.saveError { throw error }
            let id = PhotoID()
            s.images[id] = imageData
            return id
        }
    }

    func imageData(for id: PhotoID) async throws -> Data? {
        try state.withLock { s in
            if let error = s.readError { throw error }
            return s.images[id]
        }
    }

    func delete(_ id: PhotoID) async throws {
        try state.withLock { s in
            if let error = s.deleteError { throw error }
            s.images[id] = nil
            s.deleted.append(id)
        }
    }
}
