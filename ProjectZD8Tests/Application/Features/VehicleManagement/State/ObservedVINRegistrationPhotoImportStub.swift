import Foundation
@testable import ProjectZD8

/// 観測VINからの車両登録テストで、外部ファイルへアクセスせず空の画像を返す画像取込境界です。
struct ObservedVINRegistrationPhotoImportStub: VehiclePhotoImportPort {
    /// 空の画像データを返します。
    ///
    /// 責務: 画像取込要求をファイルアクセスなしで完了します。
    /// - Parameter url: 参照しない画像URL。
    /// - Returns: 空の画像データ。
    func importPhoto(at url: URL) async throws -> Data { Data() }
}
