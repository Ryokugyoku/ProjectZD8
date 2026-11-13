/// OBDのサービス番号とPID番号の組で1つの要求を識別します。
nonisolated struct OBDPIDRequest: Hashable, Codable, Sendable {
    /// OBDサービス番号です(例: 0x01)。
    let service: UInt8
    /// サービス内のPID番号です。
    let pid: UInt8

    /// サービス番号とPID番号から要求を生成します。
    ///
    /// 責務: 1件のPID要求識別値を生成します。
    init(service: UInt8, pid: UInt8) {
        self.service = service
        self.pid = pid
    }
}
