/// 接続履歴の走行距離差分に使用できる累積距離の取得元です。
enum ConnectionSessionDistanceSource: Int, Equatable, Sendable {
    /// 故障コード消去時にリセットされるService 01 PID 31です。
    case distanceSinceCodesCleared = 0
    /// 車両の累積走行距離を表すService 01 PID A6です。
    case odometer = 1

    /// 別の取得元より優先して採用できるかを返します。
    ///
    /// 責務: 2件の累積距離取得元を接続履歴での採用優先度に従って比較します。
    /// - Parameter other: 現在採用している比較対象の取得元。
    /// - Returns: 自身を比較対象より優先できる場合は `true`。
    func hasPriority(over other: ConnectionSessionDistanceSource) -> Bool {
        rawValue > other.rawValue
    }
}

/// 接続履歴の走行距離差分へ渡す取得元付き累積距離です。
struct ConnectionSessionDistanceObservation: Equatable, Sendable {
    /// 累積距離を取得した標準OBD-II PIDの意味です。
    let source: ConnectionSessionDistanceSource
    /// PID定義でキロメートルへ数値化済みの累積距離です。
    let kilometers: Double

    /// 取得元とキロメートル値を固定して生成します。
    ///
    /// 責務: 1件の標準OBD-II累積距離を取得元付き観測へ変換します。
    /// - Parameters:
    ///   - source: 累積距離を取得したPIDの意味。
    ///   - kilometers: キロメートルへ数値化済みの累積距離。
    init(source: ConnectionSessionDistanceSource, kilometers: Double) {
        self.source = source
        self.kilometers = kilometers
    }
}
