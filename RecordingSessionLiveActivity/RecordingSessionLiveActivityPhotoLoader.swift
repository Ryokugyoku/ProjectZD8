import UIKit

/// App Group共有コンテナから車両写真を読み込みます。
enum RecordingSessionLiveActivityPhotoLoader {
    /// ファイル名に対応する車両写真を読み込みます。
    ///
    /// 責務: `RecordingSessionActivityAttributes.vehiclePhotoURL(fileName:)` の場所から画像を読みます。
    /// - Parameter fileName: `ContentState.vehiclePhotoFileName` の値。
    /// - Returns: 読み込んだ画像。ファイル名が無い・共有コンテナが使えない・読めない場合は `nil`(呼び出し側がプレースホルダーを描きます)。
    static func image(fileName: String?) -> UIImage? {
        guard let fileName, let url = RecordingSessionActivityAttributes.vehiclePhotoURL(fileName: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }
}
