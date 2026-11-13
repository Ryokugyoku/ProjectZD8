/// 距離計PIDの値から、優先順位の最も高い観測元で走行距離を求めます。
nonisolated struct DistanceTracker: Equatable, Sendable {
    /// 記録すべき距離の観測結果です。
    nonisolated struct Reading: Equatable, Sendable {
        let source: DistanceSource
        let startKilometers: Double
        let endKilometers: Double

        /// 走行距離(km)です。
        var distanceKilometers: Double { endKilometers - startKilometers }
    }

    private var starts: [DistanceSource: Double] = [:]
    private var ends: [DistanceSource: Double] = [:]
    private var reported: Reading?

    /// 責務: 値をまだ観測していない追跡器を作ります。
    init() {}

    /// 責務: PID要求が距離計なら、その観測元を返します。
    static func source(for request: OBDPIDRequest) -> DistanceSource? {
        switch (request.service, request.pid) {
        case (0x21, 0x02): .vehicleSpecificOdometer
        case (0x01, 0xA6): .odometer
        case (0x01, 0x31): .distanceSinceCodesCleared
        default: nil
        }
    }

    /// 現在採用している観測結果です。
    var current: Reading? {
        for source in DistanceSource.allCases.sorted(by: { $0.priority > $1.priority }) {
            if let start = starts[source], let end = ends[source] {
                return Reading(source: source, startKilometers: start, endKilometers: end)
            }
        }
        return nil
    }

    /// 責務: 有効な距離計値を取り込み、永続化すべき観測結果が変わった場合だけ返します。
    ///
    /// 距離計が開始値より小さくなった場合はカウンターの巻き戻しとみなし、開始値を取り直します。
    mutating func record(_ kilometers: Double, for request: OBDPIDRequest) -> Reading? {
        guard let source = Self.source(for: request) else { return nil }
        if let start = starts[source] {
            if kilometers < start { starts[source] = kilometers }
        } else {
            starts[source] = kilometers
        }
        ends[source] = kilometers
        guard let current, current != reported else { return nil }
        reported = current
        return current
    }
}
