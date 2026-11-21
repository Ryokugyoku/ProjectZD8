import Foundation
@testable import ProjectZD8

/// 走行ルートの区切りのテストで、軌跡(サンプルと事象)を秒とメートルから組み立てる補助です。
enum DrivingRouteTrackFixtures {
    /// メートル単位の座標を作る補助です(原点は既定)。
    static let coordinates = GeoTestCoordinates()

    /// 基準日時から `seconds` 秒後の日時を返します。
    ///
    /// 責務: `ConnectionSessionLocationTestValues.referenceSeconds` を起点に秒を足します。
    /// - Parameter seconds: 基準日時からの秒。
    /// - Returns: 日時。
    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: ConnectionSessionLocationTestValues.referenceSeconds + seconds)
    }

    /// 位置のサンプルを作ります。
    ///
    /// 責務: 原点から東へ x m、北へ y m の座標と、秒に比例する単調時刻を持つ有効な位置を返します。
    /// - Parameters:
    ///   - sequence: セッション内の連番。
    ///   - seconds: 基準日時からの秒。
    ///   - x: 東向きの距離(m)。
    ///   - y: 北向きの距離(m)。
    ///   - accuracy: 水平精度(m)。
    /// - Returns: サンプル。
    static func sample(
        _ sequence: Int64,
        at seconds: TimeInterval,
        x: Double = 0,
        y: Double = 0,
        accuracy: Double = 5
    ) -> ConnectionSessionLocationSample {
        let point = coordinates.point(x: x, y: y)
        guard let fix = LocationFix(
            latitude: point.latitude,
            longitude: point.longitude,
            altitudeMeters: 40,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: 3,
            speedMetersPerSecond: 12.5,
            courseDegrees: 90,
            observedAt: date(seconds),
            monotonicNanoseconds: UInt64((seconds + 1_000) * 1_000_000_000)
        ) else {
            preconditionFailure("テストの位置が不変条件を満たしません")
        }
        return ConnectionSessionLocationSample(sequence: sequence, fix: fix)
    }

    /// 位置記録の事象を作ります。
    ///
    /// 責務: 番号・時刻・種類をそのまま持つ事象を返します。
    /// - Parameters:
    ///   - ordinal: 事象の番号。
    ///   - seconds: 基準日時からの秒。
    ///   - kind: 事象の種類。
    /// - Returns: 事象。
    static func event(
        _ ordinal: Int,
        at seconds: TimeInterval,
        _ kind: ConnectionSessionLocationEventKind
    ) -> ConnectionSessionLocationEvent {
        ConnectionSessionLocationEvent(ordinal: ordinal, occurredAt: date(seconds), kind: kind)
    }

    /// サンプルと事象から軌跡を作ります。
    ///
    /// 責務: 新しいセッションIDを付けて軌跡を組み立てます。
    /// - Parameters:
    ///   - samples: サンプル。
    ///   - events: 事象。
    /// - Returns: 軌跡。
    static func track(
        _ samples: [ConnectionSessionLocationSample],
        events: [ConnectionSessionLocationEvent] = []
    ) -> ConnectionSessionLocationTrack {
        ConnectionSessionLocationTrack(sessionID: ConnectionSessionID(), samples: samples, events: events)
    }

    /// ルートの区間ごとの点の連番を返します。
    ///
    /// 責務: 区間の構成を連番の二重配列へ直し、比較しやすくします。
    /// - Parameter route: 調べるルート。
    /// - Returns: 区間ごとの連番。
    static func sequences(of route: DrivingRoute) -> [[Int64]] {
        route.segments.map { $0.points.map(\.sequence) }
    }
}
