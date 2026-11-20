import Foundation

/// ZIP で使う CRC32(多項式 0xEDB88320、反転入出力)を逐次に計算します。
///
/// 表引きの自前実装です。`"123456789"` の値は `0xCBF43926` になります。
nonisolated struct CRC32Checksum: Sendable {
    /// これまでに渡したバイト列全体の CRC32。何も渡していなければ 0 です。
    private(set) var value: UInt32

    /// 空の入力に対する CRC32 から計算を始めます。
    ///
    /// 責務: 逐次計算の初期状態を作ります。
    init() {
        value = 0
    }

    /// バイト列を続けて足し、`value` を更新します。
    ///
    /// 責務: 前回までの値に続けて、渡したバイト列の CRC32 を積み上げます。
    /// - Parameter bytes: 続きのバイト列。空でもよい。
    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        var register = ~value
        Self.table.withUnsafeBufferPointer { table in
            for byte in bytes {
                register = table[Int((register ^ UInt32(byte)) & 0xFF)] ^ (register >> 8)
            }
        }
        value = ~register
    }

    /// 1バイトごとの剰余の表(256 件)。
    private static let table: [UInt32] = (0..<256).map { makeTableEntry(UInt32($0)) }

    /// 表の1件を計算します。
    ///
    /// 責務: 1バイトの値を8回シフトして、反転多項式での剰余を求めます。
    /// - Parameter index: 表の位置(0〜255)。
    /// - Returns: その位置の剰余。
    private static func makeTableEntry(_ index: UInt32) -> UInt32 {
        var entry = index
        for _ in 0..<8 {
            entry = entry & 1 == 1 ? (entry >> 1) ^ 0xEDB8_8320 : entry >> 1
        }
        return entry
    }
}
