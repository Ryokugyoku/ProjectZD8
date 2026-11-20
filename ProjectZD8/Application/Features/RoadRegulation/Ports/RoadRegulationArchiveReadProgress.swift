import Foundation

/// ZIP の読み取りの進み具合(圧縮側のバイト数)です。
nonisolated struct RoadRegulationArchiveReadProgress: Equatable, Sendable {
    /// 処理した圧縮バイト数。
    let processedCompressedBytes: Int64
    /// 圧縮バイト数の合計。
    let totalCompressedBytes: Int64
}
