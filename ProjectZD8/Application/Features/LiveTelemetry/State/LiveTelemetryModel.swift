import Observation

/// 取得中の値をチャンネルごとに保持するリアルタイム表示のモデルです。
@MainActor
@Observable
final class LiveTelemetryModel {
    /// 画面が描画する状態です。
    private(set) var state = LiveTelemetryState()

    /// 責務: 配信元を購読して値の反映を始めます。
    init(feed: any LiveTelemetryFeedPort) {
        let events = feed.subscribe()
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.apply(event)
            }
        }
    }

    /// 責務: 操作を状態遷移へ変換します。
    func send(_ action: LiveTelemetryAction) {
        switch action {
        case .clearRequested:
            guard state.status != .live else { return }
            state = LiveTelemetryState()
        }
    }

    /// 責務: 配信された出来事を状態へ反映します。開始で全体を作り直し、終了で値を古い値として残します。
    func apply(_ event: LiveTelemetryEvent) {
        switch event {
        case .sessionStarted(let session):
            var next = LiveTelemetryState()
            next.status = .live
            next.sessionID = session.sessionID
            next.adapterName = session.adapterName
            next.channels = session.channels.sorted { $0.ordinal < $1.ordinal }.map(LiveTelemetryChannel.init(spec:))
            state = next
        case .tick(let tick):
            guard state.status == .live else { return }
            for entry in tick.readings {
                guard let index = state.channels.firstIndex(where: { $0.request == entry.request }) else { continue }
                state.channels[index].apply(entry.reading, at: tick.elapsedMicroseconds)
            }
            state.elapsedMicroseconds = tick.elapsedMicroseconds
            state.sampleCount = tick.sampleCount
            state.respondedCount = tick.respondedCount
            state.distanceKilometers = tick.distanceKilometers
        case .sessionEnded(let reason):
            guard state.status == .live else { return }
            state.status = .stale(reason)
        }
    }
}
