/// リアルタイム表示の状態です。
nonisolated struct LiveTelemetryState: Equatable, Sendable {
    /// 表示している値の鮮度です。
    nonisolated enum Status: Equatable, Sendable {
        /// 記録がまだ始まっていません。
        case idle
        /// 記録中で、値は更新されています。
        case live
        /// 記録が終了しました。値は終了時点のまま(古い値)です。
        case stale(SessionEndReason)
    }

    /// 主要表示のチャンネルを決める要求です。
    static let rpmRequest = OBDPIDRequest(service: 0x01, pid: 0x0C)
    static let speedRequest = OBDPIDRequest(service: 0x01, pid: 0x0D)

    var status: Status = .idle
    var sessionID: SessionID?
    var adapterName: String?
    /// 全チャンネルです。セッション内の並び順に並びます。
    var channels: [LiveTelemetryChannel] = []
    /// 開始からの経過時間(マイクロ秒)です。
    var elapsedMicroseconds: Int64 = 0
    /// 記録した要求の総数です。
    var sampleCount = 0
    /// データ付きで応答した要求の数です。
    var respondedCount = 0
    /// 走行距離(km)です。距離計PIDが未取得なら `nil` です。
    var distanceKilometers: Double?

    /// 責務: 初期状態を生成します。
    init() {}

    /// エンジン回転数のチャンネルです。収集対象に無ければ `nil` です。
    var rpm: LiveTelemetryChannel? { channel(for: Self.rpmRequest) }
    /// 車速のチャンネルです。収集対象に無ければ `nil` です。
    var speed: LiveTelemetryChannel? { channel(for: Self.speedRequest) }
    /// データ付き応答の割合(0...1)です。
    var responseRate: Double { sampleCount == 0 ? 0 : Double(respondedCount) / Double(sampleCount) }
    /// 値が終了時点の古い値かどうかです。
    var isStale: Bool {
        if case .stale = status { return true }
        return false
    }

    /// 責務: 要求に対応するチャンネルを返します。
    func channel(for request: OBDPIDRequest) -> LiveTelemetryChannel? {
        channels.first { $0.request == request }
    }

    /// 責務: 分類に属するチャンネルを並び順のまま返します。
    func channels(in category: OBDPIDCategory) -> [LiveTelemetryChannel] {
        channels.filter { $0.category == category }
    }
}
