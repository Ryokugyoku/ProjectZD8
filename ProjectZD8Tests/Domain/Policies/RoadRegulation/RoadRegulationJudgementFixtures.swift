import Foundation
@testable import ProjectZD8

/// 規制の判定(4つの Judge と集計)のテストで、区間の通過・一時停止の通過・車速の時系列・軌跡の点を組み立てる補助です。
///
/// 軌跡の点は緯度0・経度0を原点にした「北へ何 m・東へ何 m」で作ります。緯度0の付近では
/// 1度 = 111,195.08 m(設計書 §3.3 の k)で、北向きの2点間の距離は Δ緯度 × k になります。
enum RoadRegulationJudgementFixtures {
    /// 設計書 §3.3 の k(m/度)。テスト側で独立に持ちます。
    static let metersPerDegree = 111_195.08
    /// 判定の対象にする規制の ID です(既定引数からも使うため隔離しません)。
    nonisolated static let regulationID = RoadRegulationID(rawValue: 7)
    /// 実時間の基準(時刻軸の0秒)です。
    private static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// 責務: 時刻軸の秒と連番から、状態が変わった点の印を作ります。
    /// - Parameters:
    ///   - time: 時刻軸の秒。
    ///   - sequence: 位置サンプルの連番。
    /// - Returns: 点の印。
    static func mark(at time: TimeInterval, sequence: Int64 = 0) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: time, sequence: sequence, observedAt: referenceDate.addingTimeInterval(time))
    }

    /// 責務: 経路の状態と区間の窓 [from, to] から、記録の空白で終わっていない区間の通過を作ります。
    /// - Parameters:
    ///   - status: 区間の状態。
    ///   - from: 区間の最初の点の時刻。
    ///   - to: 区間の最後の点の時刻。
    ///   - sequences: 区間の最初と最後の点の連番。
    /// - Returns: 区間の通過。
    static func traversal(
        _ status: RoadRegulationTraversalStatus,
        from: TimeInterval,
        to: TimeInterval,
        sequences: ClosedRange<Int64> = 0...100
    ) -> RoadRegulationTraversal {
        RoadRegulationTraversal(
            status: status,
            start: mark(at: from, sequence: sequences.lowerBound),
            end: mark(at: to, sequence: sequences.upperBound),
            endReason: .changed
        )
    }

    /// 責務: 制限速度 `limitKph` の規制に乗った最高速度の区間を作ります。
    /// - Parameters:
    ///   - limitKph: 制限速度(km/h)。
    ///   - from: 区間の最初の点の時刻。
    ///   - to: 区間の最後の点の時刻。
    /// - Returns: 最高速度の経路の区間。
    static func speedLimitTraversal(limitKph: Int, from: TimeInterval, to: TimeInterval) -> RoadRegulationTraversal {
        traversal(.speedLimit(.regulated(regulationID, limitKph: limitKph)), from: from, to: to)
    }

    /// 責務: 開始・到達の時刻と条件の判定から、一時停止の通過を作ります。
    /// - Parameters:
    ///   - startedAt: 接近を始めた時刻。
    ///   - reachedAt: 到達した時刻。
    ///   - applicability: 条件の判定。
    ///   - interruptedByGap: 記録の空白で到達扱いにしたか。
    /// - Returns: 一時停止の通過。
    static func stopPassage(
        startedAt: TimeInterval,
        reachedAt: TimeInterval,
        applicability: RegulationApplicability = .applies,
        interruptedByGap: Bool = false
    ) -> StopPassage {
        StopPassage(
            key: StopApproachKey(regulationID: regulationID, approachIndex: 0),
            approachStarted: mark(at: startedAt, sequence: 10),
            reached: mark(at: reachedAt, sequence: 14),
            applicability: applicability,
            interruptedByGap: interruptedByGap
        )
    }

    /// 責務: (時刻, 車速) の組から車速の時系列を作ります。
    /// - Parameter samples: (時刻の秒, km/h) の組。
    /// - Returns: 車速の時系列。
    static func timeline(_ samples: [(TimeInterval, Double)]) -> VehicleSpeedTimeline {
        VehicleSpeedTimeline(samples: samples.map { VehicleSpeedSample(time: $0.0, kph: $0.1) })
    }

    /// 責務: 整数秒 `seconds` の各時刻に同じ車速を置いた (時刻, 車速) の組を作ります。
    /// - Parameters:
    ///   - kph: 車速(km/h)。
    ///   - seconds: 時刻(整数秒)の範囲。
    /// - Returns: (時刻の秒, km/h) の組。
    static func steady(_ kph: Double, over seconds: ClosedRange<Int>) -> [(TimeInterval, Double)] {
        seconds.map { (TimeInterval($0), kph) }
    }

    /// 責務: 原点(緯度0・経度0)から北と東へ何 m の位置に、軌跡の点を作ります。
    /// - Parameters:
    ///   - sequence: 連番(時刻の秒にも使う)。
    ///   - northMeters: 北への距離(m)。
    ///   - eastMeters: 東への距離(m)。
    ///   - accuracy: 水平精度(m)。
    /// - Returns: 軌跡の点。
    static func trackPoint(
        sequence: Int64,
        northMeters: Double,
        eastMeters: Double = 0,
        accuracy: Double = 5
    ) -> RoadRegulationTrackPoint {
        guard let coordinate = GeoCoordinate(latitude: northMeters / metersPerDegree, longitude: eastMeters / metersPerDegree) else {
            preconditionFailure("テストの座標を作れません: north=\(northMeters) east=\(eastMeters)")
        }
        return RoadRegulationTrackPoint(
            sequence: sequence,
            time: TimeInterval(sequence),
            observedAt: referenceDate.addingTimeInterval(TimeInterval(sequence)),
            coordinate: coordinate,
            horizontalAccuracyMeters: accuracy,
            courseDegrees: 180,
            gpsSpeedMetersPerSecond: 5
        )
    }

    /// 責務: 北への距離と精度の組から、連番 0, 1, 2, … の軌跡を作ります。
    /// - Parameter points: (北への距離 m, 東への距離 m, 水平精度 m) の組。
    /// - Returns: 軌跡の点(連番の昇順)。
    static func track(_ points: [(north: Double, east: Double, accuracy: Double)]) -> [RoadRegulationTrackPoint] {
        points.enumerated().map { index, point in
            trackPoint(sequence: Int64(index), northMeters: point.north, eastMeters: point.east, accuracy: point.accuracy)
        }
    }

    /// 責務: 軌跡の最初と最後の点を両端に持つ、一方通行の経路の区間を作ります。
    /// - Parameters:
    ///   - status: 一方通行の経路の状態。
    ///   - track: 区間の点。空なら連番0の1点の区間にします。
    /// - Returns: 一方通行の経路の区間。
    static func oneWayTraversal(_ status: OneWayChannelStatus, over track: [RoadRegulationTrackPoint]) -> RoadRegulationTraversal {
        let first = track.first?.sequence ?? 0
        let last = track.last?.sequence ?? first
        return traversal(.oneWay(status), from: TimeInterval(first), to: TimeInterval(last), sequences: first...last)
    }
}
