import Foundation

/// 記録中表示に使う車両写真を、表示側(Widget Extension)から読める場所へ置く境界です。
@MainActor
protocol SessionActivityVehiclePhotoPort: AnyObject {
    /// 車両写真を表示用に縮小して保存し、以前に保存した写真を消します。
    ///
    /// 責務: 1台分の写真データを表示用ファイルへ置き換えます。
    /// - Parameters:
    ///   - photoData: 車両プロフィールの写真データ。
    ///   - vehicleID: 写真の持ち主の車両ID。
    /// - Returns: 表示側へ渡すファイル名。
    /// - Throws: 画像として読めない、共有コンテナが使えない、または書き込みに失敗した場合。
    func replacePhoto(with photoData: Data, for vehicleID: VehicleID) throws -> String

    /// 保存済みの表示用写真をすべて消します。
    ///
    /// 責務: 表示用写真ファイルを残さないようにします。
    /// - Throws: 共有コンテナが使えない、または削除に失敗した場合。
    func removeAllPhotos() throws
}
