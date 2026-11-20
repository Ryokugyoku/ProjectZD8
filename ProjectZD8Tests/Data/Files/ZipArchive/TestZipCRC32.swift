import Foundation

/// テスト側で独立に持つ CRC32 の素直な実装です(製品の `CRC32Checksum` を呼びません。表を使わずビットごとに計算します)。
nonisolated enum TestZipCRC32 {
    /// 反転した生成多項式(IEEE 802.3)です。
    private static let polynomial: UInt32 = 0xEDB8_8320

    /// 責務: バイト列の CRC32 を、ビットごとの計算で求めます。
    /// - Parameter bytes: 対象のバイト列。
    /// - Returns: CRC32 の値。
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ polynomial : crc >> 1
            }
        }
        return ~crc
    }
}
