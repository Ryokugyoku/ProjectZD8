import Foundation

/// 記録中のセッションの要約です。
nonisolated struct ActiveSessionSummary: Equatable, Sendable {
    let sessionID: SessionID
    let vehicleName: String
    let adapterName: String
    let adapterTransport: AdapterTransport
    /// デモモードの模擬データかどうかです。
    let isDemo: Bool
    let startedAt: Date
    /// 開始からの経過時間(マイクロ秒)です。ティックごとに更新します。
    var elapsedMicroseconds: Int64
    /// 完了したティック数です。
    var tickCount: Int
    /// 記録した要求の総数です(無応答を含む)。
    var sampleCount: Int
    /// データ付きで応答した要求の数です。
    var respondedCount: Int
    /// 走行距離(km)です。距離計PIDが未取得なら `nil` です。
    var distanceKilometers: Double?

    /// データ付き応答の割合(0...1)です。要求が無ければ 0 です。
    var responseRate: Double { sampleCount == 0 ? 0 : Double(respondedCount) / Double(sampleCount) }

    /// 開始からの経過時間(秒)です。
    var elapsedSeconds: TimeInterval { TimeInterval(elapsedMicroseconds) / 1_000_000 }
}
