/// `ATMA`受信監視の1行から復元したCANフレームです。
nonisolated struct ELM327CANFrame: Equatable, Sendable {
    /// フレームのCAN IDです。
    let canIdentifier: UInt32
    /// 29bit拡張IDならtrue、11bit標準IDならfalseです。
    let isExtended: Bool
    /// 0〜8バイトのデータです。
    let payload: [UInt8]
}
