#if os(iOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 記録中表示用の車両写真を縮小し、Widget Extensionから読めるApp Group共有コンテナへ保存するiOS実装です。
@MainActor
final class AppGroupSessionActivityVehiclePhotoStore: SessionActivityVehiclePhotoPort {
    /// 縮小後の長辺のピクセル数です(長辺160pt相当を3倍密度で表す値)。
    static let maximumPixelLength = 480
    /// JPEGの圧縮品質です。
    static let compressionQuality = 0.8

    /// ファイル操作に使うファイルマネージャーです。
    private let fileManager: FileManager
    /// 写真を置くディレクトリのURLを返す処理です。共有コンテナが使えなければ `nil` を返します。
    private let directoryURL: () -> URL?

    /// 保存先を固定して生成します。
    ///
    /// 責務: 写真ディレクトリの取得元とファイル操作の境界を受け取ります。
    /// - Parameters:
    ///   - fileManager: ファイル操作に使うファイルマネージャー。
    ///   - directoryURL: 写真ディレクトリのURLを返す処理。既定はApp Group共有コンテナ内のディレクトリ。
    init(
        fileManager: FileManager = .default,
        directoryURL: @escaping () -> URL? = { RecordingSessionActivityAttributes.vehiclePhotoDirectoryURL() }
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
    }

    /// 車両写真を縮小して保存し、以前に保存した写真を消します。
    ///
    /// 責務: 写真データを長辺 `maximumPixelLength` 以下のJPEGへ変換し、ディレクトリ内の唯一のファイルにします。
    /// - Parameters:
    ///   - photoData: 車両プロフィールの写真データ。
    ///   - vehicleID: 写真の持ち主の車両ID。ファイル名に使います。
    /// - Returns: 保存したファイル名。表示が古い画像を使い回さないよう、保存ごとに異なる名前です。
    /// - Throws: `AppGroupSessionActivityVehiclePhotoStoreError`、またはファイル操作のエラー。
    func replacePhoto(with photoData: Data, for vehicleID: VehicleID) throws -> String {
        let directory = try preparedDirectory()
        let thumbnail = try makeThumbnail(from: photoData)
        try removeAllPhotos()
        let fileName = "\(vehicleID.rawValue.uuidString)-\(UUID().uuidString).jpg"
        try writeJPEG(thumbnail, to: directory.appendingPathComponent(fileName, isDirectory: false))
        return fileName
    }

    /// 保存済みの表示用写真をすべて消します。
    ///
    /// 責務: 写真ディレクトリ内のファイルをすべて削除します。ディレクトリが無ければ何もしません。
    /// - Throws: 共有コンテナが使えなければ `containerUnavailable`、削除に失敗すればファイル操作のエラー。
    func removeAllPhotos() throws {
        guard let directory = directoryURL() else { throw AppGroupSessionActivityVehiclePhotoStoreError.containerUnavailable }
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for file in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: file)
        }
    }

    /// 写真ディレクトリを用意します。
    ///
    /// 責務: 共有コンテナ内の写真ディレクトリを、無ければ作って返します。
    /// - Returns: 写真ディレクトリのURL。
    /// - Throws: 共有コンテナが使えなければ `containerUnavailable`、作成に失敗すればファイル操作のエラー。
    private func preparedDirectory() throws -> URL {
        guard let directory = directoryURL() else { throw AppGroupSessionActivityVehiclePhotoStoreError.containerUnavailable }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 写真データから縮小画像を作ります。
    ///
    /// 責務: 向き補正済みで長辺 `maximumPixelLength` 以下の画像へ変換します。
    /// - Parameter photoData: 元の写真データ。
    /// - Returns: 縮小画像。
    /// - Throws: 画像として読めなければ `undecodableImage`。
    private func makeThumbnail(from photoData: Data) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelLength
        ]
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppGroupSessionActivityVehiclePhotoStoreError.undecodableImage
        }
        return thumbnail
    }

    /// 画像をJPEGとして書き出します。
    ///
    /// 責務: 1枚の画像を指定URLへJPEGで保存します。
    /// - Parameters:
    ///   - image: 書き出す画像。
    ///   - url: 保存先。
    /// - Throws: 書き出せなければ `encodingFailed`。
    private func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppGroupSessionActivityVehiclePhotoStoreError.encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Self.compressionQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AppGroupSessionActivityVehiclePhotoStoreError.encodingFailed
        }
    }
}
#endif
