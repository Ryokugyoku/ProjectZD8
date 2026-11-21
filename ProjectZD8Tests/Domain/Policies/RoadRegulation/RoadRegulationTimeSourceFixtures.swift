import Foundation
@testable import ProjectZD8

/// 時刻軸・車速・軌跡のテストで、位置・車速の入力を作る補助です。
enum RoadRegulationTimeSourceFixtures {
    /// 実時間の基準(参照日時からの秒)です。
    static let baseWallSeconds: TimeInterval = 800_000_000

    /// 責務: 実時間と単調時計のずれ(実時間 − 単調時刻、秒)を指定して、位置1点を作ります。
    /// - Parameters:
    ///   - sequence: セッション内の連番。
    ///   - monotonicSeconds: 単調時刻(秒)。
    ///   - offset: 実時間 − 単調時刻(秒)。
    ///   - accuracy: 水平精度(m)。
    ///   - latitude: 緯度。
    /// - Returns: 位置サンプル。
    static func location(
        _ sequence: Int64,
        monotonicSeconds: Double,
        offset: Double = 0,
        accuracy: Double = 5,
        latitude: Double = 26.2
    ) -> ConnectionSessionLocationSample {
        guard let fix = LocationFix(
            latitude: latitude,
            longitude: 127.7,
            altitudeMeters: nil,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: nil,
            speedMetersPerSecond: 8,
            courseDegrees: 90,
            observedAt: Date(timeIntervalSinceReferenceDate: baseWallSeconds + monotonicSeconds + offset),
            monotonicNanoseconds: UInt64(monotonicSeconds * 1_000_000_000)
        ) else { fatalError("位置を作れません") }
        return ConnectionSessionLocationSample(sequence: sequence, fix: fix)
    }

    /// 責務: 単調時刻の有無とずれを指定して、車速の生の観測を作ります。
    /// - Parameters:
    ///   - monotonicSeconds: 単調時刻(秒)。`nil` なら単調時刻なし。
    ///   - offset: 実時間 − 単調時刻(秒)。単調時刻が無い時は基準からの秒として使います。
    ///   - kph: 車速。
    /// - Returns: 車速の観測。
    static func speed(monotonicSeconds: Double?, offset: Double = 0, kph: Double = 40) -> VehicleSpeedRawObservation {
        VehicleSpeedRawObservation(
            observedAt: Date(timeIntervalSinceReferenceDate: baseWallSeconds + (monotonicSeconds ?? 0) + offset),
            monotonicNanoseconds: monotonicSeconds.map { UInt64($0 * 1_000_000_000) },
            kph: kph
        )
    }

    /// 責務: OBD の生ログ1件を作ります。
    /// - Parameters:
    ///   - service: Service 番号。
    ///   - pid: PID 番号。
    ///   - payload: 応答データバイト。
    ///   - monotonic: 単調時計のナノ秒。
    /// - Returns: 生ログ。
    static func rawEntry(service: UInt8 = 0x01, pid: UInt8 = 0x0D, payload: [UInt8], monotonic: UInt64? = 7_000_000_000) -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: 1,
            observedAt: Date(timeIntervalSinceReferenceDate: baseWallSeconds + 7),
            batchElapsedNanoseconds: 0,
            service: service,
            pid: pid,
            payload: payload,
            monotonicNanoseconds: monotonic
        )
    }
}
