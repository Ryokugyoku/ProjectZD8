import Foundation

/// 位置サンプルと車速の観測値を、選んだ時刻の軸に載せて、突き合わせに使う軌跡と車速の時系列を作ります。
///
/// 軌跡では、水平精度が上限を超える点と、直前に残した点より時刻が戻る点を捨てて数えます。残す点は渡された順を保ちます。
nonisolated struct RoadRegulationTrackBuilder: Sendable {
    /// OBD の車速(PID 0x0D、1バイト)が取り得る範囲(km/h)。
    static let validSpeedRangeKph: ClosedRange<Double> = 0...255
    /// 1秒のナノ秒数。
    private static let nanosecondsPerSecond = 1_000_000_000.0

    /// 使える点の水平精度の上限などのしきい値。
    private let thresholds: RoadRegulationMatchingThresholds

    /// しきい値から作ります。
    ///
    /// 責務: 点を捨てる基準に使うしきい値を保持します。
    /// - Parameter thresholds: しきい値。既定は設計どおりの初期値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 位置サンプルから軌跡を作ります。
    ///
    /// 責務: 渡された順に点を時刻の軸へ載せ、精度が悪い点・座標を作れない点・時刻が戻る点を捨てて数えます。
    /// - Parameters:
    ///   - samples: 位置サンプル(連番の昇順を想定)。
    ///   - axis: 時刻の軸。
    /// - Returns: 残した点(渡された順)と、捨てた点の数。
    func build(_ samples: [ConnectionSessionLocationSample], axis: RoadRegulationTimeAxis) -> (points: [RoadRegulationTrackPoint], droppedCount: Int) {
        var points: [RoadRegulationTrackPoint] = []
        points.reserveCapacity(samples.count)
        for sample in samples {
            guard let point = trackPoint(from: sample, axis: axis), point.time >= (points.last?.time ?? -.infinity) else { continue }
            points.append(point)
        }
        return (points, samples.count - points.count)
    }

    /// 車速の観測値から時系列を作ります。
    ///
    /// 責務: 観測値を時刻の軸へ載せ、範囲外・有限でない車速と、単調時計の軸で単調時刻の無い観測値を除きます。
    /// - Parameters:
    ///   - observations: 車速の観測値。
    ///   - axis: 時刻の軸。
    /// - Returns: 時刻の昇順の時系列(同じ時刻は後の値)。
    func speedTimeline(_ observations: [VehicleSpeedRawObservation], axis: RoadRegulationTimeAxis) -> VehicleSpeedTimeline {
        let samples = observations.compactMap { observation -> VehicleSpeedSample? in
            guard Self.validSpeedRangeKph.contains(observation.kph) else { return nil }
            let monotonic = observation.monotonicNanoseconds
            guard let time = Self.time(observedAt: observation.observedAt, monotonicNanoseconds: monotonic, axis: axis) else { return nil }
            return VehicleSpeedSample(time: time, kph: observation.kph)
        }
        return VehicleSpeedTimeline(samples: samples)
    }

    /// 位置サンプル1点を軌跡の点に直します。
    ///
    /// 責務: 精度の上限と座標の妥当性を確かめ、時刻の軸の秒を付けます。
    /// - Parameters:
    ///   - sample: 位置サンプル。
    ///   - axis: 時刻の軸。
    /// - Returns: 使えない点なら `nil`。
    private func trackPoint(from sample: ConnectionSessionLocationSample, axis: RoadRegulationTimeAxis) -> RoadRegulationTrackPoint? {
        let fix = sample.fix
        guard fix.horizontalAccuracyMeters <= thresholds.maximumUsableHorizontalAccuracyMeters,
              let coordinate = GeoCoordinate(latitude: fix.latitude, longitude: fix.longitude),
              let time = Self.time(observedAt: fix.observedAt, monotonicNanoseconds: fix.monotonicNanoseconds, axis: axis)
        else { return nil }
        return RoadRegulationTrackPoint(
            sequence: sample.sequence,
            time: time,
            observedAt: fix.observedAt,
            coordinate: coordinate,
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
            courseDegrees: fix.courseDegrees,
            gpsSpeedMetersPerSecond: fix.speedMetersPerSecond
        )
    }

    /// 時刻の軸の秒を返します。
    ///
    /// 責務: 単調時計なら単調時刻を秒に、実時間なら 1970年からの秒にします。
    /// - Parameters:
    ///   - observedAt: 実時間。
    ///   - monotonicNanoseconds: 単調時刻(ナノ秒)。
    ///   - axis: 時刻の軸。
    /// - Returns: 単調時計の軸で単調時刻が無ければ `nil`。
    private static func time(observedAt: Date, monotonicNanoseconds: UInt64?, axis: RoadRegulationTimeAxis) -> TimeInterval? {
        switch axis {
        case .wallClock:
            observedAt.timeIntervalSince1970
        case .monotonic:
            monotonicNanoseconds.map { Double($0) / nanosecondsPerSecond }
        }
    }
}
