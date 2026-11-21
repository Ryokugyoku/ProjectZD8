/// 位置を取得する唯一の口です。消費者は配布役の1つだけで、消費している間だけ取得します。
@MainActor
protocol LocationUpdateSourcePort: AnyObject {
    /// 位置の流れを作ります。
    ///
    /// 責務: 呼び出しごとに位置の取得を始める流れを返し、流れの消費が終わったら取得を止めます。
    /// - Returns: 位置または取得不可の通知の流れ。
    func makeUpdates() -> AsyncStream<LocationUpdateEvent>
}
