import Foundation

/// 常駐リンク監視が使う現在時刻と、キャンセル可能な待機を提供する能力です。
@MainActor
protocol AdapterLinkSupervisionClock: AnyObject {
    /// 現在時刻です。
    var now: Date { get }

    /// 指定した時間だけ待機します。
    ///
    /// 責務: 再確認間隔の待機を、呼び出し元のタスクのキャンセルに従って終えます。
    /// - Parameter duration: 待機する時間。
    /// - Throws: 待機中にタスクがキャンセルされた場合の `CancellationError`。
    func sleep(for duration: Duration) async throws
}
