import CoreGraphics
import Foundation
import ImageIO

/// 画像バイト列のデコード失敗。
nonisolated enum VehicleImageDecodingError: Error, Equatable {
    /// バイト列が空。
    case emptyData
    /// ImageIO が画像として解釈できなかった。
    case undecodable
}

/// 画像バイト列を ImageIO で縮小デコードする(UIImage / NSImage に依存しない)。
nonisolated enum VehicleImageDecoder {
    /// 長辺を `maxPixelSize` 以内に収めてデコードする。
    ///
    /// 責務: 向きを反映したサムネイル CGImage を返し、空・不正データは型付きエラーで失敗する。
    static func decode(_ data: Data, maxPixelSize: Int = 512) throws -> CGImage {
        guard !data.isEmpty else { throw VehicleImageDecodingError.emptyData }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw VehicleImageDecodingError.undecodable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VehicleImageDecodingError.undecodable
        }
        return image
    }

    /// 車両名からモノグラム(頭文字最大2文字)を作る。
    ///
    /// 責務: 空白区切りの先頭語から最大2語の頭文字を大文字化して返す。空なら空文字。
    static func monogram(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}
