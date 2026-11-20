import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの判定・状態・地図の内容・モデルのテストが共有する、軌跡と区切った軌跡の値を作ります。
///
/// 点は緯度を 0.0001 度(約 11 m)ずつ、時刻を1秒ずつずらすため、区切りのしきい値(10 s・90 m/s)に掛かりません。
enum DrivingRouteTestValues {
    /// 観測日時の基準(1970年起点の秒)です。
    static let referenceSeconds: TimeInterval = 1_800_000_000
    /// 点の基準の緯度です。
    static let baseLatitude = 35.0
    /// 点の基準の経度です。
    static let baseLongitude = 139.0
    /// 番号1つあたりの緯度のずれ(度)です。
    static let latitudeStep = 0.000_1

    /// 基準日時から指定秒だけ後の日時を返します。
    ///
    /// 責務: テストの時刻を基準からの秒で表せるようにします。
    /// - Parameter seconds: 基準からの秒。
    /// - Returns: 日時。
    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: referenceSeconds + seconds)
    }

    /// 緯度経度から座標を作ります。
    ///
    /// 責務: 不正な値ならテストを失敗させ、有効な座標を返します。
    /// - Parameters:
    ///   - latitude: 緯度。
    ///   - longitude: 経度。
    /// - Returns: 座標。
    /// - Throws: 座標を作れない場合のテスト失敗。
    static func coordinate(latitude: Double, longitude: Double) throws -> GeoCoordinate {
        try XCTUnwrap(GeoCoordinate(latitude: latitude, longitude: longitude), "テスト用の座標が不正です")
    }

    /// 番号に応じた位置のサンプルを作ります。
    ///
    /// 責務: 番号から緯度・時刻・単調時計を決め、指定の水平精度を持つサンプルを返します。
    /// - Parameters:
    ///   - index: 0 以上の番号(sequence と時刻の秒にも使います)。
    ///   - horizontalAccuracyMeters: 水平精度。
    /// - Returns: サンプル。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func sample(index: Int, horizontalAccuracyMeters: Double = 5) throws -> ConnectionSessionLocationSample {
        let fix = try XCTUnwrap(
            LocationFix(
                latitude: baseLatitude + Double(index) * latitudeStep,
                longitude: baseLongitude,
                altitudeMeters: 40,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                verticalAccuracyMeters: 3,
                speedMetersPerSecond: 11,
                courseDegrees: 0,
                observedAt: date(TimeInterval(index)),
                monotonicNanoseconds: UInt64(index + 1) * 1_000_000_000
            ),
            "テスト用の位置が不変条件を満たしません"
        )
        return ConnectionSessionLocationSample(sequence: Int64(index), fix: fix)
    }

    /// 番号 0 から連続するサンプルを作ります。
    ///
    /// 責務: 指定件数のサンプルを、同じ水平精度で番号順に返します。
    /// - Parameters:
    ///   - count: 件数。
    ///   - horizontalAccuracyMeters: 水平精度。
    /// - Returns: sequence 昇順のサンプル。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func samples(count: Int, horizontalAccuracyMeters: Double = 5) throws -> [ConnectionSessionLocationSample] {
        try (0..<count).map { try sample(index: $0, horizontalAccuracyMeters: horizontalAccuracyMeters) }
    }

    /// 種類の列から、ordinal と時刻が昇順の状態変化を作ります。
    ///
    /// 責務: 最初のサンプルより前(基準の -100 秒から1秒ずつ)に起きた状態変化を返します。
    /// - Parameter kinds: 起きた順の種類。
    /// - Returns: 状態変化。
    static func events(_ kinds: [ConnectionSessionLocationEventKind]) -> [ConnectionSessionLocationEvent] {
        kinds.enumerated().map { ordinal, kind in
            ConnectionSessionLocationEvent(ordinal: ordinal, occurredAt: date(TimeInterval(ordinal) - 100), kind: kind)
        }
    }

    /// 軌跡を作ります。
    ///
    /// 責務: サンプルと状態変化の種類の列から、1セッションの軌跡を返します。
    /// - Parameters:
    ///   - sessionID: セッション。
    ///   - samples: サンプル。
    ///   - eventKinds: 起きた順の状態変化の種類。
    /// - Returns: 軌跡。
    static func track(
        sessionID: ConnectionSessionID = ConnectionSessionID(),
        samples: [ConnectionSessionLocationSample] = [],
        eventKinds: [ConnectionSessionLocationEventKind] = []
    ) -> ConnectionSessionLocationTrack {
        ConnectionSessionLocationTrack(sessionID: sessionID, samples: samples, events: events(eventKinds))
    }

    /// 区切った軌跡の点を作ります。
    ///
    /// 責務: 指定の座標と、番号から決まる時刻を持つ点を返します。
    /// - Parameters:
    ///   - index: 番号(sequence と時刻の秒に使います)。
    ///   - latitude: 緯度。
    ///   - longitude: 経度。
    /// - Returns: 点。
    /// - Throws: 座標を作れない場合のテスト失敗。
    static func point(index: Int, latitude: Double, longitude: Double = baseLongitude) throws -> DrivingRoutePoint {
        DrivingRoutePoint(
            sequence: Int64(index),
            coordinate: try coordinate(latitude: latitude, longitude: longitude),
            observedAt: date(TimeInterval(index)),
            monotonicNanoseconds: UInt64(index + 1) * 1_000_000_000,
            horizontalAccuracyMeters: 5,
            altitudeMeters: nil,
            verticalAccuracyMeters: nil
        )
    }

    /// 番号の範囲から、緯度が番号で決まりジグザグに経度が揺れる区間を作ります。
    ///
    /// 責務: 一直線にならない(間引きで点が減らない)点の列を、指定の精度の区間として返します。
    /// - Parameters:
    ///   - indices: 点の番号の範囲。
    ///   - precision: 区間の精度の段階。
    /// - Returns: 区間。
    /// - Throws: 座標を作れない場合のテスト失敗。
    static func segment(_ indices: Range<Int>, precision: DrivingRoutePrecision = .precise) throws -> DrivingRouteSegment {
        let points = try indices.map { index in
            try point(
                index: index,
                latitude: baseLatitude + Double(index) * latitudeStep * 10,
                longitude: baseLongitude + (index.isMultiple(of: 2) ? 0 : 0.001)
            )
        }
        return DrivingRouteSegment(points: points, precision: precision)
    }

    /// 区切った軌跡を作ります。
    ///
    /// 責務: 区間と件数から軌跡を返します。全点数を省いた時は区間の点の数を使います。
    /// - Parameters:
    ///   - segments: 区間。
    ///   - totalFixCount: 全サンプル数。`nil` なら区間の点の合計。
    ///   - excludedFixCount: 除いた数。
    /// - Returns: 区切った軌跡。
    static func route(
        _ segments: [DrivingRouteSegment],
        totalFixCount: Int? = nil,
        excludedFixCount: Int = 0
    ) -> DrivingRoute {
        DrivingRoute(
            segments: segments,
            totalFixCount: totalFixCount ?? segments.reduce(0) { $0 + $1.points.count },
            excludedFixCount: excludedFixCount
        )
    }

    /// 開始日時と、終了済みかを指定してセッションを作ります。
    ///
    /// 責務: 基準日時に始まり、終了済みなら 60 秒後に終わったセッションを返します。
    /// - Parameters:
    ///   - id: セッション ID。
    ///   - hasEnded: 終了済みか。
    /// - Returns: セッション。
    static func session(id: ConnectionSessionID = ConnectionSessionID(), hasEnded: Bool = true) -> ConnectionSession {
        var session = ConnectionSession(id: id, accountIdentifier: "account", startedAt: date(-100))
        if hasEnded {
            session.endedAt = date(60)
            session.endReason = .userDisconnected
        }
        return session
    }
}
