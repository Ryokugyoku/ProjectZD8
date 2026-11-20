import Foundation

/// テスト用の ZIP を組み立てる時の、リトルエンディアンのバイト書き込み器です。
nonisolated struct TestZipByteWriter {
    /// ここまでに書いたバイト列です。
    private(set) var bytes: [UInt8] = []

    /// 責務: 2バイトの整数をリトルエンディアンで末尾へ足します。
    /// - Parameter value: 足す値。
    mutating func append16(_ value: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    /// 責務: 4バイトの整数をリトルエンディアンで末尾へ足します。
    /// - Parameter value: 足す値。
    mutating func append32(_ value: UInt32) {
        append16(UInt16(truncatingIfNeeded: value))
        append16(UInt16(truncatingIfNeeded: value >> 16))
    }

    /// 責務: バイト列をそのまま末尾へ足します。
    /// - Parameter other: 足すバイト列。
    mutating func append(_ other: [UInt8]) {
        bytes.append(contentsOf: other)
    }
}
