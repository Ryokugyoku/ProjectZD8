/// 応答駆動ポーリングの各周回で照会するPIDの優先順位と間引き周期を決定します。
///
/// 周回は固定時間間隔ではなく、前の周回の全要求が応答または失敗で終わった時点で次へ進みます。
nonisolated struct OBDPIDPollingPolicy: Sendable {
    /// 高頻度更新する一般用途PIDです。
    private static let highPriorityRequests: Set<OBDPIDRequest> = [
        OBDPIDRequest(service: 0x01, pid: 0x04),
        OBDPIDRequest(service: 0x01, pid: 0x0C),
        OBDPIDRequest(service: 0x01, pid: 0x0D),
        OBDPIDRequest(service: 0x01, pid: 0x11)
    ]

    /// 対応済みPIDから現在の周回で照会する定義を選びます。
    ///
    /// 責務: 高優先PIDを毎周回、その他を8周回ごと(周回番号が8の倍数の時)に含む読取順へ変換します。
    /// - Parameters:
    ///   - definitions: 初回探索で応答が確認できたPID定義。
    ///   - tick: 応答駆動の周回番号。0から始まり、前の周回の全要求が終わるたびに1増えます。経過時間とは無関係です。
    /// - Returns: 高優先順、Service/PID順に整列した今回の読取対象。
    func definitionsToPoll(from definitions: [OBDPIDDefinition], tick: UInt) -> [OBDPIDDefinition] {
        let isHigh = { (definition: OBDPIDDefinition) in
            Self.highPriorityRequests.contains(OBDPIDRequest(service: definition.service, pid: definition.pid))
        }
        let high = definitions.filter(isHigh)
        let normal = definitions.filter { !isHigh($0) }
        if tick.isMultiple(of: 8) || high.isEmpty { return high + normal }
        return high
    }
}

