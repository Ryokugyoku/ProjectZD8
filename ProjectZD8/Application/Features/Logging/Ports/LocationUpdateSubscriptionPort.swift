/// 位置の受け手(保存・将来の音声案内)が購読する口です。
@MainActor
protocol LocationUpdateSubscriptionPort: AnyObject {
    /// 位置の流れを購読します。
    ///
    /// 責務: 購読者ごとの独立した流れを返し、購読が続く間だけ位置の取得を保ちます。
    /// - Returns: 位置または取得不可の通知の流れ。
    func subscribe() -> AsyncStream<LocationUpdateEvent>
}
