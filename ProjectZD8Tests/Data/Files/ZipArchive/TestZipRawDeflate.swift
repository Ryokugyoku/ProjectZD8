import Compression
import Foundation

/// テスト用に raw deflate(RFC 1951)を作る部品です(Compression の `COMPRESSION_ZLIB` は raw deflate です)。
nonisolated enum TestZipRawDeflate {
    /// 空の入力に対する、最小の raw deflate(最終ブロックの空の固定ハフマン符号)です。
    private static let emptyStream: [UInt8] = [0x03, 0x00]

    /// 責務: バイト列を raw deflate へ圧縮します。
    /// - Parameter input: 圧縮する元のバイト列。
    /// - Returns: raw deflate のバイト列。
    static func compress(_ input: [UInt8]) -> [UInt8] {
        if input.isEmpty { return emptyStream }
        var output = [UInt8](repeating: 0, count: input.count + input.count / 8 + 1_024)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_encode_buffer(
                    destination.baseAddress!, destination.count,
                    source.baseAddress!, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        precondition(written > 0, "テスト用の deflate 圧縮に失敗しました")
        return Array(output.prefix(written))
    }
}
