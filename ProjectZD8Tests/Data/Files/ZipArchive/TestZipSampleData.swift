import Foundation

/// ZIP のテストで使う、再現可能な元データを作ります。
nonisolated enum TestZipSampleData {
    /// 責務: 圧縮率の高い、短い模様の繰り返しを作ります。
    /// - Parameter count: バイト数。
    /// - Returns: 繰り返しのバイト列。
    static func repetitive(count: Int) -> [UInt8] {
        let pattern = Array("0123456789,ABCDEF\r\n".utf8)
        return [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            for index in 0..<count { buffer[index] = pattern[index % pattern.count] }
            initialized = count
        }
    }

    /// 責務: 固定の種から、圧縮の効かない擬似乱数のバイト列を作ります。
    /// - Parameters:
    ///   - count: バイト数。
    ///   - seed: 種。
    /// - Returns: 乱数に近いバイト列。
    static func pseudoRandom(count: Int, seed: UInt64) -> [UInt8] {
        var generator = TestZipSeededGenerator(seed: seed)
        return [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            var word: UInt64 = 0
            for index in 0..<count {
                if index % 8 == 0 { word = generator.next() }
                buffer[index] = UInt8(truncatingIfNeeded: word >> UInt64(8 * (index % 8)))
            }
            initialized = count
        }
    }
}
