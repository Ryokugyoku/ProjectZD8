import Foundation
@testable import ProjectZD8

/// 表示用写真の境界の偽物です。呼び出しを記録し、指定した失敗を返します。
@MainActor
final class SessionActivityVehiclePhotoPortSpy: SessionActivityVehiclePhotoPort {
    /// 保存要求の車両IDです。
    private(set) var storedVehicleIDs: [VehicleID] = []
    /// 保存要求の写真データです。
    private(set) var storedPhotoData: [Data] = []
    /// 全削除が呼ばれた回数です。
    private(set) var removeAllCount = 0
    /// 保存成功時に返すファイル名です。
    var storedFileName = "vehicle-photo.jpg"
    /// 設定すると保存がこのエラーを投げます。
    var replaceError: (any Error)?
    /// 設定すると全削除がこのエラーを投げます。
    var removeError: (any Error)?

    /// 保存要求を記録します。
    ///
    /// 責務: 要求を記録し、エラー指定が無ければファイル名を返します。
    func replacePhoto(with photoData: Data, for vehicleID: VehicleID) throws -> String {
        storedPhotoData.append(photoData)
        storedVehicleIDs.append(vehicleID)
        if let replaceError { throw replaceError }
        return storedFileName
    }

    /// 全削除を記録します。
    ///
    /// 責務: 回数を数え、エラー指定があれば投げます。
    func removeAllPhotos() throws {
        removeAllCount += 1
        if let removeError { throw removeError }
    }
}
