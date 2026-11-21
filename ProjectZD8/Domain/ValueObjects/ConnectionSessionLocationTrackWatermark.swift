/// 追記だけの位置表の「どこまで」を表す水位です。等しければ内容も同じとみなします。
nonisolated struct ConnectionSessionLocationTrackWatermark: Equatable, Sendable {
    /// サンプルの件数。
    let sampleCount: Int
    /// 最後のサンプルの sequence。サンプルが無ければ nil。
    let lastSampleSequence: Int64?
    /// 事象の件数。
    let eventCount: Int
    /// 最後の事象の ordinal。事象が無ければ nil。
    let lastEventOrdinal: Int?

    /// サンプルも事象も無い水位。
    static let empty = ConnectionSessionLocationTrackWatermark(
        sampleCount: 0,
        lastSampleSequence: nil,
        eventCount: 0,
        lastEventOrdinal: nil
    )
}
