import Foundation

/// 実時刻と `Task.sleep` で、常駐リンク監視の時刻と待機を提供します。
@MainActor
final class SystemAdapterLinkSupervisionClock: AdapterLinkSupervisionClock {
    /// 現在の実時刻です。
    var now: Date { Date() }

    /// 指定した時間だけ待機します。
    ///
    /// 責務: 呼び出し元タスクのキャンセルに従って待機を終えます。
    /// - Parameter duration: 待機する時間。
    /// - Throws: 待機中にキャンセルされた場合の `CancellationError`。
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
