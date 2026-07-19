/// OBDのServiceとPIDを組にした読取要求識別子です。
struct OBDPIDRequest: Equatable, Hashable, Sendable {
    /// OBD Service番号です。
    let service: UInt8
    /// Service内PID番号です。
    let pid: UInt8

    /// ServiceとPIDを複合識別子へ固定します。
    ///
    /// 責務: 1件のOBD読取対象をService/PIDの組として保持します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    init(service: UInt8, pid: UInt8) {
        self.service = service
        self.pid = pid
    }
}
