import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルート記録のテストが共有する有効な位置の値を生成します。
enum ConnectionSessionLocationTestValues {
    /// 位置の観測日時の基準(1970年起点の秒)です。
    static let referenceSeconds: TimeInterval = 1_800_000_000

    /// 緯度経度と時刻を指定して有効な位置を作ります。
    ///
    /// 責務: 標高・精度・速度・進行方向を妥当な固定値にした位置を返します。
    /// - Parameters:
    ///   - latitude: 緯度(度)。
    ///   - longitude: 経度(度)。
    ///   - secondsAfterReference: 基準日時からの経過秒。
    ///   - monotonicNanoseconds: 単調時計(ナノ秒)。
    /// - Returns: 不変条件を満たす位置。
    /// - Throws: 指定値が不変条件を満たさず位置を作れない場合のテスト失敗。
    static func fix(
        latitude: Double = 35.681_236,
        longitude: Double = 139.767_125,
        secondsAfterReference: TimeInterval = 0,
        monotonicNanoseconds: UInt64 = 1_000_000_000
    ) throws -> LocationFix {
        try XCTUnwrap(
            LocationFix(
                latitude: latitude,
                longitude: longitude,
                altitudeMeters: 40,
                horizontalAccuracyMeters: 5,
                verticalAccuracyMeters: 3,
                speedMetersPerSecond: 12.5,
                courseDegrees: 90,
                observedAt: Date(timeIntervalSince1970: referenceSeconds + secondsAfterReference),
                monotonicNanoseconds: monotonicNanoseconds
            ),
            "テスト用の位置が不変条件を満たしません"
        )
    }

    /// 番号ごとに互いに異なる有効な位置を作ります。
    ///
    /// 責務: 番号に応じて緯度経度・時刻・単調時計をずらし、区別できる位置を返します。
    /// - Parameter index: 0 以上の番号。
    /// - Returns: 番号に対応する位置。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func fix(index: Int) throws -> LocationFix {
        try fix(
            latitude: 35.0 + Double(index) * 0.001,
            longitude: 139.0 + Double(index) * 0.001,
            secondsAfterReference: TimeInterval(index),
            monotonicNanoseconds: UInt64(index + 1) * 1_000_000_000
        )
    }
}
