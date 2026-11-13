/// セッションの走行距離を求めた観測元です。
nonisolated enum DistanceSource: String, Codable, CaseIterable, Sendable {
    /// 故障コード消去後の走行距離(01/31)。
    case distanceSinceCodesCleared
    /// 標準オドメーター(01/A6)。
    case odometer
    /// 車種専用オドメーター(例: ZD8 21/02)。
    case vehicleSpecificOdometer

    /// 値が大きいほど信頼度が高い優先順位です。
    var priority: Int {
        switch self {
        case .distanceSinceCodesCleared: 0
        case .odometer: 1
        case .vehicleSpecificOdometer: 2
        }
    }
}
