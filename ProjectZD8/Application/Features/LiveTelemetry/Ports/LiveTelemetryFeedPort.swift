/// 取得中の値をリアルタイム表示へ届ける契約です。
@MainActor
protocol LiveTelemetryFeedPort: AnyObject {
    /// 責務: 以降の取得の出来事を受け取る購読を開始します。購読ごとに独立したストリームを返します。
    func subscribe() -> AsyncStream<LiveTelemetryEvent>
}
