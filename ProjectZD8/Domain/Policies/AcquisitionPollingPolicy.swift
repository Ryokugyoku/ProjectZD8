/// 各ティックでどのPIDを要求するかを決める方針です。
///
/// 高頻度グループは毎ティック要求し、それ以外は1ティックあたり数件ずつ巡回します。
/// 低頻度PIDをまとめて要求して高頻度PIDの間隔が延びることを防ぎます。
nonisolated struct AcquisitionPollingPolicy: Sendable {
    /// この方針の版です。選択規則を変えるたびに増やし、セッションへ記録します。
    static let version = 1

    /// 既定で高頻度グループにする標準PIDです(負荷・回転数・車速・スロットル開度)。
    static let defaultFastRequests: Set<OBDPIDRequest> = [
        OBDPIDRequest(service: 0x01, pid: 0x04),
        OBDPIDRequest(service: 0x01, pid: 0x0C),
        OBDPIDRequest(service: 0x01, pid: 0x0D),
        OBDPIDRequest(service: 0x01, pid: 0x11)
    ]

    /// 1ティックで巡回する低頻度PIDの件数です。
    let slowRequestsPerTick: Int

    /// 方針を生成します。
    ///
    /// 責務: 低頻度PIDの巡回件数を固定します。
    init(slowRequestsPerTick: Int = 2) {
        self.slowRequestsPerTick = max(1, slowRequestsPerTick)
    }

    /// 指定ティックで要求するPIDを要求順に返します。
    ///
    /// 責務: 高頻度グループ全件と、巡回位置にある低頻度PIDを選びます。
    /// - Parameters:
    ///   - tick: 0始まりのティック番号。
    ///   - pids: セッションの取得条件。`isPolled` が偽のものは選びません。
    /// - Returns: このティックで要求するPID。
    func pidsToPoll(tick: Int, from pids: [SessionPID]) -> [SessionPID] {
        let polled = pids.filter(\.isPolled)
        let fast = polled.filter(\.isFastGroup)
        let slow = polled.filter { !$0.isFastGroup }
        guard !slow.isEmpty else { return fast }
        let count = min(slowRequestsPerTick, slow.count)
        let start = (tick * count) % slow.count
        let rotated = (0..<count).map { slow[(start + $0) % slow.count] }
        return fast + rotated
    }
}
