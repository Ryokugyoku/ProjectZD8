import Foundation

/// 写真の画像本体の永続化契約です。画像はファイルとして保存し、車両に所属させます。
nonisolated protocol PhotoRepository: Sendable {
    /// 責務: 画像を車両の写真として保存し、新しい写真IDを返します。
    func save(_ imageData: Data, for vehicleID: VehicleID) async throws -> PhotoID
    /// 責務: 写真の画像データを返します。この端末に無ければ `nil` を返します。
    func imageData(for id: PhotoID) async throws -> Data?
    /// 責務: 写真を削除します。
    func delete(_ id: PhotoID) async throws
}
