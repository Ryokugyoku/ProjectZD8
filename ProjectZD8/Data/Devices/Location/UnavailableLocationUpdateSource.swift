import Foundation

/// 位置を扱わないプラットフォーム(macOS)用の位置の取得元です。すぐ終わる流れを返し、何も取得しません。
@MainActor
final class UnavailableLocationUpdateSource: LocationUpdateSourcePort {
    /// 状態を持たない取得元を生成します。
    ///
    /// 責務: 何も取得しない取得元を構築します。
    init() {}

    /// 要素を流さずにすぐ終わる流れを返します。
    ///
    /// 責務: 位置を取得せず、終了済みの流れを1つ返します。
    /// - Returns: 要素のない終了済みの流れ。
    func makeUpdates() -> AsyncStream<LocationUpdateEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
