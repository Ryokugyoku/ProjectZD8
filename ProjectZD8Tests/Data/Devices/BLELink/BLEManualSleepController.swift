import Foundation
@testable import ProjectZD8

/// 実時間を待たず、テストが明示的に発火させるまで戻らない待機手段です。
@MainActor
final class BLEManualSleepController {
    /// 要求された待機時間を要求順に保持します。
    private(set) var requestedDurations: [Duration] = []
    /// 待機を呼んだタスクがキャンセルされた要求の位置です。
    private(set) var cancelledIndices: Set<Int> = []
    /// まだ戻していない待機の継続です。
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]

    /// リンクへ注入する待機処理です。
    var sleep: BLEAdapterLinkDeadline.Sleep {
        { [self] duration in try await self.suspend(for: duration) }
    }

    /// 要求された待機の件数です。
    var requestCount: Int { requestedDurations.count }

    /// キャンセルされていない待機要求の位置です。
    var activeIndices: [Int] {
        continuations.keys.filter { !cancelledIndices.contains($0) }.sorted()
    }

    /// 指定位置の待機を戻し、期限切れとして扱わせます。
    ///
    /// 責務: 1件の待機をエラーなしで戻します。既に戻した位置は何もしません。
    /// - Parameter index: 戻す要求の位置。
    func fire(_ index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }

    /// 残っている全ての待機をキャンセルエラーで戻します。
    ///
    /// 責務: テスト終了時に継続を取り残さないよう全件を終わらせます。
    func drain() {
        let pending = continuations
        continuations.removeAll()
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
    }

    /// 待機要求を記録し、テストが戻すまで中断します。
    ///
    /// 責務: 要求を記録して継続を保持し、呼び出し元タスクのキャンセルを記録します。
    /// - Parameter duration: 要求された待機時間。
    private func suspend(for duration: Duration) async throws {
        let index = requestedDurations.count
        requestedDurations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                continuations[index] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.markCancelled(index) }
        }
    }

    /// キャンセルされた要求の位置を記録します。
    ///
    /// 責務: 古い期限として発火させられるよう継続は残したまま位置だけ記録します。
    /// - Parameter index: キャンセルされた要求の位置。
    private func markCancelled(_ index: Int) {
        cancelledIndices.insert(index)
    }
}
