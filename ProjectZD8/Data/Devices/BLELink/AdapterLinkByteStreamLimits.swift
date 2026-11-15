/// 常駐リンク上のバイトストリームが使う待機上限と容量の値です。
nonisolated struct AdapterLinkByteStreamLimits: Equatable, Sendable {
    /// 実運用の値です。占有待ち15秒、リンク状態確認0.1秒間隔、受信バッファー64KiB。
    static let standard = AdapterLinkByteStreamLimits(
        leaseTimeout: .seconds(15),
        linkCheckInterval: .milliseconds(100),
        receiveBufferCapacity: 64 * 1024
    )

    /// 他の利用者が占有している時に占有権を待つ上限です。
    let leaseTimeout: Duration
    /// 読取中にリンク状態と期限を確認する間隔です。
    let linkCheckInterval: Duration
    /// 受信バッファーに溜められる最大バイト数です。
    let receiveBufferCapacity: Int

    /// 待機上限と容量を固定して生成します。
    ///
    /// 責務: バイトストリームの待機と溜め込みの上限を1件の値へまとめます。
    /// - Parameters:
    ///   - leaseTimeout: 占有権を待つ上限。
    ///   - linkCheckInterval: 読取中の確認間隔。
    ///   - receiveBufferCapacity: 受信バッファーの最大バイト数。
    init(leaseTimeout: Duration, linkCheckInterval: Duration, receiveBufferCapacity: Int) {
        self.leaseTimeout = leaseTimeout
        self.linkCheckInterval = linkCheckInterval
        self.receiveBufferCapacity = receiveBufferCapacity
    }

    /// 指定時間を確認間隔で割った確認回数です。
    ///
    /// 責務: 待機ループの上限回数を、端数を切り上げた1以上の整数で返します。
    /// - Parameter duration: 待機する時間。
    /// - Returns: 確認間隔ごとに待つ回数。
    func checkCount(for duration: Duration) -> Int {
        guard linkCheckInterval > .zero else { return 1 }
        let ratio = duration / linkCheckInterval
        guard ratio.isFinite, ratio > 1 else { return 1 }
        return Int(ratio.rounded(.up))
    }
}
