/// リアルタイムPID更新の優先順位と間引き周期を決定します。
struct OBDPIDPollingPolicy {
    /// 高頻度更新する一般用途PIDです。
    private static let highPriorityRequests: Set<OBDPIDRequest> = [
        OBDPIDRequest(service: 0x01, pid: 0x04),
        OBDPIDRequest(service: 0x01, pid: 0x0C),
        OBDPIDRequest(service: 0x01, pid: 0x0D),
        OBDPIDRequest(service: 0x01, pid: 0x11)
    ]

    /// 対応済みPIDから現在tickで照会する定義を選びます。
    ///
    /// 責務: 高優先PIDを毎tick、その他を8tickごとに含む読取順へ変換します。
    /// - Parameters:
    ///   - definitions: 初回探索で応答が確認できたPID定義。
    ///   - tick: 0から単調増加する更新番号。
    /// - Returns: 高優先順、Service/PID順に整列した今回の読取対象。
    func definitionsToPoll(from definitions: [OBDPIDDefinition], tick: UInt) -> [OBDPIDDefinition] {
        let high = definitions.filter { Self.highPriorityRequests.contains($0.request) }
        let normal = definitions.filter { !Self.highPriorityRequests.contains($0.request) }
        if tick.isMultiple(of: 8) || high.isEmpty { return high + normal }
        return high
    }
}

/// PID定義から読取要求を復元します。
private extension OBDPIDDefinition {
    /// この定義が表すService/PID要求です。
    var request: OBDPIDRequest { OBDPIDRequest(service: service, pid: pid) }
}
