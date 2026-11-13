import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 保存する写真をJPEGへ正規化します。
nonisolated enum PhotoImageNormalizer {
    /// 長辺の上限ピクセル数です。
    static let maximumPixelSize = 2048
    /// JPEGの圧縮品質です。
    static let compressionQuality = 0.8

    /// 責務: 画像データをデコードし、向きを反映して長辺を上限以下に縮小したJPEGへ変換します。デコードできなければ `StoreError.ioFailure` を投げます。
    static func normalizedJPEG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw StoreError.ioFailure
        }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw StoreError.ioFailure }
        // 縮小のみ行い、小さな画像を拡大しない。
        let targetSize = min(maximumPixelSize, max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StoreError.ioFailure
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw StoreError.ioFailure
        }
        let destinationOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.ioFailure }
        return output as Data
    }
}
