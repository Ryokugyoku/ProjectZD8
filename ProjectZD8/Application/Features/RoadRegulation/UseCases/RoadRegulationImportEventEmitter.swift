import Foundation
import Synchronization

/// 取り込みの事象を、間引きながら1本の流れへ順に送る型です。
///
/// ダウンロードの進捗は URLSession の委譲のキューから、ほかの段階は取り込みの Task から届くため、
/// 間引きの状態と送出を1つの錠で守り、届いた順のまま流します。
/// - ダウンロードの進捗は、いまの段階がダウンロードの時だけ流します(ダウンロードが終わった後に遅れて届いた進捗で、段階が戻らないように)。
/// - ダウンロードで受け取ったバイト数の最大を覚えます(ZIP の大きさが読めない時の代わり)。
nonisolated final class RoadRegulationImportEventEmitter: Sendable {
    /// 錠で守る状態です。
    private struct Storage: Sendable {
        /// 進捗の間引き。
        var throttle: RoadRegulationProgressThrottle
        /// 最後に受け付けた段階の順番。
        var currentStage: Int?
        /// ダウンロードで受け取ったバイト数の最大。
        var largestReceivedBytes: Int64 = 0
    }

    /// 事象の送り先。
    private let continuation: AsyncThrowingStream<RoadRegulationImportEvent, any Error>.Continuation
    /// 段階の順番の計算。
    private let fractions = RoadRegulationImportProgressFraction()
    /// 錠で守る状態。
    private let storage: Mutex<Storage>

    /// 送り先と間引きを受け取ります。
    ///
    /// 責務: 事象の送出に使う状態を作ります。
    /// - Parameters:
    ///   - continuation: 事象の送り先。
    ///   - throttle: 進捗の間引き。
    init(
        continuation: AsyncThrowingStream<RoadRegulationImportEvent, any Error>.Continuation,
        throttle: RoadRegulationProgressThrottle = .init()
    ) {
        self.continuation = continuation
        storage = Mutex(Storage(throttle: throttle))
    }

    /// ダウンロードで受け取ったバイト数の最大。
    var largestReceivedBytes: Int64 {
        storage.withLock { $0.largestReceivedBytes }
    }

    /// 段階の進捗を、間引いて流します。
    ///
    /// 責務: いまの段階を更新し、間引きを通った時だけ流します。
    /// - Parameter phase: 新しい段階。
    func report(_ phase: RoadRegulationImportPhase) {
        let stage = fractions.stage(of: phase)
        storage.withLock { state in
            state.currentStage = stage
            guard state.throttle.shouldEmit(phase) else { return }
            continuation.yield(.progress(phase))
        }
    }

    /// ダウンロードの進捗を、ダウンロードの段階の間だけ間引いて流します。
    ///
    /// 責務: 受け取ったバイト数の最大を覚え、段階がダウンロードの時だけ流します。
    /// - Parameter progress: 受け取りの進み具合。
    func reportDownload(_ progress: RoadRegulationTransferProgress) {
        let phase = RoadRegulationImportPhase.downloading(progress)
        let downloadingStage = fractions.stage(of: phase)
        storage.withLock { state in
            state.largestReceivedBytes = max(state.largestReceivedBytes, progress.receivedBytes)
            guard state.currentStage == downloadingStage, state.throttle.shouldEmit(phase) else { return }
            continuation.yield(.progress(phase))
        }
    }

    /// 完了を流して、流れを閉じます。
    ///
    /// 責務: 有効にした版を最後の事象として送ります。
    /// - Parameter dataset: 有効にした版。
    func complete(with dataset: RoadRegulationDataset) {
        storage.withLock { _ in
            continuation.yield(.completed(dataset))
            continuation.finish()
        }
    }

    /// 失敗で流れを閉じます。
    ///
    /// 責務: 分類済みの失敗を、流れの終わりとして送ります。
    /// - Parameter error: 取り込みのエラーか `CancellationError`。
    func fail(with error: any Error) {
        storage.withLock { _ in
            continuation.finish(throwing: error)
        }
    }
}
