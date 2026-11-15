/// 取得対象・周回番号・batch番号の進み方を保持します。
///
/// 正応答が1件以上あった最初の周回で以後の取得対象を確定します。確定までは全定義を周回番号0で送り続けます。
nonisolated struct LiveTelemetryPollingCursor: Equatable, Sendable {
    /// 現在の取得対象です。確定前は開始時の全定義です。
    private(set) var targets: [OBDPIDDefinition]
    /// polling policyへ渡す周回番号です。
    private(set) var tick: UInt = 0
    /// セッション内(世代内)のbatch番号です。
    private(set) var batchOrdinal: Int64 = 0
    /// 取得対象を確定したかどうかです。
    private(set) var isConfirmed = false

    /// 開始時の全定義から周回を始めます。
    ///
    /// 責務: 取得対象・周回番号・batch番号を初期状態で構築します。
    /// - Parameter definitions: 開始時の取得対象定義。
    init(definitions: [OBDPIDDefinition]) {
        targets = definitions
    }

    /// 最後まで送り終えた周回の結果を反映して次の周回へ進めます。
    ///
    /// 責務: 未確定なら正応答のあったPIDで取得対象を確定し、batch番号と(確定後の)周回番号を進めます。
    /// - Parameter outcome: 周回の要求結果の集計。
    /// - Returns: この周回で取得対象を確定した場合はその対象。それ以外は `nil`。
    mutating func advance(after outcome: LiveTelemetryRoundOutcome) -> [OBDPIDDefinition]? {
        batchOrdinal += 1
        guard !isConfirmed else {
            tick &+= 1
            return nil
        }
        guard !outcome.respondedRequests.isEmpty else { return nil }
        let responded = Set(outcome.respondedRequests)
        targets = targets.filter { responded.contains(OBDPIDRequest(service: $0.service, pid: $0.pid)) }
        isConfirmed = true
        tick &+= 1
        return targets
    }

    /// 途切れて途中で打ち切った周回の次へ進めます。
    ///
    /// 責務: 打ち切ったbatchの番号を再利用しないようbatch番号を進め、確定後なら周回番号も進めます。
    mutating func abandonRound() {
        batchOrdinal += 1
        if isConfirmed { tick &+= 1 }
    }
}
