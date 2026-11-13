import Foundation

/// 取得の出来事をリアルタイム表示の購読者へ複数配信します。
@MainActor
final class LiveTelemetryFeedBroadcaster: LiveTelemetryFeedPort, AcquisitionEventPublishing {
    private var continuations: [Int: AsyncStream<LiveTelemetryEvent>.Continuation] = [:]
    private var nextToken = 0

    /// 責務: 購読者のいない配信元を作ります。
    init() {}

    /// 責務: 新しい購読を登録します。ストリームが終了すると登録を外します。
    func subscribe() -> AsyncStream<LiveTelemetryEvent> {
        let token = nextToken
        nextToken += 1
        let (stream, continuation) = AsyncStream<LiveTelemetryEvent>.makeStream()
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.continuations[token] = nil }
        }
        return stream
    }

    /// 責務: 取得の出来事を表示用の出来事へ変換して全購読者へ流します。
    func publish(_ event: AcquisitionEvent) {
        let converted: LiveTelemetryEvent
        switch event {
        case .started(let start):
            converted = .sessionStarted(Self.session(from: start))
        case .tick(let tick):
            converted = .tick(.init(
                elapsedMicroseconds: tick.elapsedMicroseconds,
                readings: tick.readings.map { .init(request: $0.request, reading: Self.reading(from: $0.reading)) },
                sampleCount: tick.sampleCount,
                respondedCount: tick.respondedCount,
                distanceKilometers: tick.distanceKilometers
            ))
        case .ended(let session):
            converted = .sessionEnded(session.endReason ?? .acquisitionFailed)
        }
        for continuation in continuations.values { continuation.yield(converted) }
    }

    /// 責務: 開始情報から、収集有効なPIDだけの表示チャンネル一覧を作ります。
    private static func session(from start: AcquisitionEvent.Start) -> LiveTelemetryEvent.Session {
        let channels = start.pids.filter(\.isPolled).map { pid in
            LiveTelemetryEvent.ChannelSpec(
                request: pid.request,
                ordinal: pid.ordinal,
                nameKey: OBDPIDCatalog.definition(for: pid.request, vehicleModelCode: start.vehicleModelCode)?.nameKey
                    ?? String(format: "obd.pid.%02X.%02X.name", pid.request.service, pid.request.pid),
                unit: pid.unit,
                minimumValue: pid.minimumValue,
                maximumValue: pid.maximumValue
            )
        }
        return .init(sessionID: start.session.id, adapterName: start.session.adapterName, channels: channels)
    }

    /// 責務: 取得側の解釈結果を表示側の値状態へ写します。
    private static func reading(from reading: AcquisitionEvent.Reading) -> LiveTelemetryEvent.Reading {
        switch reading {
        case .value(let value): .value(value)
        case .outOfRange(let value): .outOfRange(value)
        case .decodeFailed: .decodeFailed
        case .noResponse(let outcome): .noResponse(outcome)
        }
    }
}
