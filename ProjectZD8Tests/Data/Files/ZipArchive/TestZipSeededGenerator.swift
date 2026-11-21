import Foundation

/// 固定の種から同じ列を作る擬似乱数です(SplitMix64。`SystemRandomNumberGenerator` を使わずテストを再現可能にします)。
nonisolated struct TestZipSeededGenerator: RandomNumberGenerator {
    /// 内部の状態です。
    private var state: UInt64

    /// 責務: 種から生成器を作ります。
    /// - Parameter seed: 種。
    init(seed: UInt64) {
        state = seed
    }

    /// 責務: 次の64ビットの値を返します。
    /// - Returns: 擬似乱数。
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
