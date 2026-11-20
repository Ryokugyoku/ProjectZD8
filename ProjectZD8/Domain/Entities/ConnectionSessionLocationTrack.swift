/// 1セッションの軌跡(サンプルと事象)です。
nonisolated struct ConnectionSessionLocationTrack: Equatable, Sendable {
    /// 軌跡を所有する接続セッション。
    let sessionID: ConnectionSessionID
    /// 位置のサンプル(sequence 昇順)。
    let samples: [ConnectionSessionLocationSample]
    /// 位置記録の状態変化(ordinal 昇順)。
    let events: [ConnectionSessionLocationEvent]

    /// 軌跡を作ります。
    ///
    /// 責務: セッションID・サンプル・事象をそのまま保持します。
    init(
        sessionID: ConnectionSessionID,
        samples: [ConnectionSessionLocationSample],
        events: [ConnectionSessionLocationEvent]
    ) {
        self.sessionID = sessionID
        self.samples = samples
        self.events = events
    }

    /// サンプルも事象も無い時に true。
    var isEmpty: Bool {
        samples.isEmpty && events.isEmpty
    }

    /// 現在の件数と最後の番号から成る水位。空なら `.empty`。
    var watermark: ConnectionSessionLocationTrackWatermark {
        ConnectionSessionLocationTrackWatermark(
            sampleCount: samples.count,
            lastSampleSequence: samples.last?.sequence,
            eventCount: events.count,
            lastEventOrdinal: events.last?.ordinal
        )
    }
}
