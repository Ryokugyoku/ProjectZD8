import Foundation
@testable import ProjectZD8

/// 取得ループの出来事ストリームを件数上限付きで購読し、受けた出来事を保持します。
///
/// 購読はストリームの終了、`cancel()`、または `maximumEvents` 件の受信で終わります。
/// テストはこの購読を待たず、`LiveTelemetryBoundedWaiter` で保持内容を上限付きで確認します。
@MainActor
final class LiveTelemetryAcquisitionEventCollector {
    /// 受け取る出来事の上限です。
    static let maximumEvents = 10_000

    /// 受けた出来事です。受けた順に並びます。
    private(set) var events: [LiveTelemetryAcquisitionEvent] = []
    /// ストリームが終わったかどうかです。
    private(set) var isFinished = false
    /// 購読Taskです。
    private var task: Task<Void, Never>?

    /// ストリームの購読を始めます。
    ///
    /// 責務: 出来事を上限件数まで受け取り、保持するTaskを開始します。
    /// - Parameter stream: 取得ループが返したストリーム。
    init(_ stream: AsyncStream<LiveTelemetryAcquisitionEvent>) {
        task = Task { [weak self] in
            var received = 0
            for await event in stream {
                guard let self else { return }
                self.events.append(event)
                received += 1
                if received >= Self.maximumEvents { break }
            }
            self?.isFinished = true
        }
    }

    /// 受けた数値化済み観測です。受けた順に並びます。
    var samples: [OBDPIDSample] {
        events.compactMap { if case let .sampleDecoded(sample) = $0 { sample } else { nil } }
    }

    /// 受けた終了理由です。まだ終わっていなければ `nil` です。
    var termination: LiveTelemetryAcquisitionTermination? {
        events.lazy.compactMap { if case let .ended(termination) = $0 { termination } else { nil } }.first
    }

    /// 受けた取得対象の確定です。受けた順に並びます。
    var confirmedTargets: [[OBDPIDDefinition]] {
        events.compactMap { if case let .targetsConfirmed(definitions) = $0 { definitions } else { nil } }
    }

    /// 購読をやめます。
    ///
    /// 責務: 購読Taskを取り消し、ストリームの購読終了を取得ループへ伝えます。
    func cancel() {
        task?.cancel()
    }
}
