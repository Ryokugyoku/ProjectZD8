/// `AdapterLinkBoundedAwait.value(_:operation:)` の待ちが上限内に終わらなかったことを表すエラーです。
nonisolated struct AdapterLinkBoundedAwaitTimeout: Error, Equatable {
    /// 終わらなかった待機の内容です。
    let description: String
}
