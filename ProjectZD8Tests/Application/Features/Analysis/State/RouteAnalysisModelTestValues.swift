import Foundation
@testable import ProjectZD8

/// 解析の走行ルートのモデルのテストが共有する、ルート・PID の時系列・重ね合わせの値です。
///
/// 位置の点 i は、時刻が基準の i 秒後(`DrivingRouteTestValues.date(i)`)、単調時刻が (i + 1) 秒、緯度が 0.0001 度(約 11 m)ずつ北です。
/// PID のサンプルも同じ時刻と単調時刻で作るため、時計がどちらに決まっても値と位置の時刻は一致します。
enum RouteAnalysisModelTestValues {
    /// テストで使うアカウント識別子です。
    static let account = "account"
    /// 重ね合わせの ID です。
    static let overlayID = "test-overlay"

    /// 番号 i の位置の点を作ります。
    ///
    /// 責務: 番号から時刻・単調時刻・座標・標高(40 + i m、垂直精度 3 m)を決めた点を返します。
    /// - Parameter index: 0 以上の番号(sequence にも使います)。
    /// - Returns: 点。
    static func point(_ index: Int) -> DrivingRoutePoint {
        guard let coordinate = GeoCoordinate(
            latitude: DrivingRouteTestValues.baseLatitude + Double(index) * DrivingRouteTestValues.latitudeStep,
            longitude: DrivingRouteTestValues.baseLongitude
        ) else {
            preconditionFailure("テストの座標が範囲外です")
        }
        return DrivingRoutePoint(
            sequence: Int64(index),
            coordinate: coordinate,
            observedAt: DrivingRouteTestValues.date(TimeInterval(index)),
            monotonicNanoseconds: UInt64(index + 1) * 1_000_000_000,
            horizontalAccuracyMeters: 5,
            altitudeMeters: 40 + Double(index),
            verticalAccuracyMeters: 3
        )
    }

    /// 番号 0 から `pointCount` 点の、1区間のルートを作ります。
    ///
    /// 責務: 正確な区間1つのルートを返します。
    /// - Parameter pointCount: 点の数。
    /// - Returns: ルート。
    static func route(pointCount: Int) -> DrivingRoute {
        DrivingRoutePointFixtures.route([DrivingRoutePointFixtures.segment((0..<pointCount).map(point))])
    }

    /// 番号 0 からの点に合わせた PID のサンプルを作ります。
    ///
    /// 責務: 値の i 番目を位置の点 (i + secondsOffset) と同じ時刻・単調時刻に置き、連番を `sequenceOffset + i` にします。
    /// - Parameters:
    ///   - pid: PID 番号(Service は 0x01)。
    ///   - values: 値の列。
    ///   - unit: 単位。
    ///   - sequenceOffset: 連番の起点。
    ///   - secondsOffset: 時刻と単調時刻を後ろへずらす秒(位置と時刻が合わない値を作る時に使います)。
    /// - Returns: サンプル。
    static func samples(
        pid: UInt8,
        values: [Double],
        unit: String,
        sequenceOffset: Int64 = 0,
        secondsOffset: Int = 0
    ) -> [SessionLogAnalysisState.TimelineSample] {
        values.enumerated().map { index, value in
            let seconds = index + secondsOffset
            return RouteAnalysisTimelineSampleFixtures.sample(
                sequence: sequenceOffset + Int64(index),
                observedAt: DrivingRouteTestValues.date(TimeInterval(seconds)),
                pid: pid,
                value: value,
                unit: unit,
                monotonicNanoseconds: UInt64(seconds + 1) * 1_000_000_000
            )
        }
    }

    /// 10 点のうち前半 5 点が 10 km/h(区分0)、後半 5 点が 50 km/h(区分2)の車速のサンプルです。
    ///
    /// 責務: 色分けで区分0と区分2の2色になる車速を返します。
    /// - Returns: サンプル。
    static func speedSamples() -> [SessionLogAnalysisState.TimelineSample] {
        samples(pid: 0x0D, values: (0..<10).map { $0 < 5 ? 10 : 50 }, unit: "km/h")
    }

    /// 10 点のうち前半 5 点が 1,000 rpm(区分0)、後半 5 点が 5,000 rpm(区分4)のエンジン回転のサンプルです。
    ///
    /// 責務: 色分けで区分0と区分4の2色になるエンジン回転を返します。
    /// - Returns: サンプル。
    static func engineSpeedSamples() -> [SessionLogAnalysisState.TimelineSample] {
        samples(pid: 0x0C, values: (0..<10).map { $0 < 5 ? 1_000 : 5_000 }, unit: "rpm", sequenceOffset: 1_000)
    }

    /// 番号 2〜4 の点を注意の色にし、点 2〜4 の時刻を強調する重ね合わせを作ります。
    ///
    /// 責務: 連番の範囲と時刻の範囲を持つ重ね合わせを返します。
    /// - Returns: 重ね合わせ。
    static func overlay() -> RouteAnalysisOverlay {
        RouteAnalysisOverlay(
            id: overlayID,
            titleKey: "test.overlay",
            runs: [RouteAnalysisColorRun(sequenceRange: 2...4, category: .tone(.caution))],
            legend: [RouteAnalysisLegendEntry(id: 0, category: .tone(.caution), text: "caution")],
            highlightedTimeRanges: [DrivingRouteTestValues.date(2)...DrivingRouteTestValues.date(4)]
        )
    }
}
