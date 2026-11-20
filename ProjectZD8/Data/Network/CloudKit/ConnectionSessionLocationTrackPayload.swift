import Foundation

/// iCloud へ送る軌跡の符号化表現です。JSON のキー名は保存済みデータの形式なので変更しません。
///
/// 事象の種類を増やす時や、フィールドの意味を変える時は `currentFormatVersion` を上げます。
nonisolated struct ConnectionSessionLocationTrackPayload: Codable, Equatable, Sendable {
    /// この版のアプリが書き出し、読み取れる形式の版です。
    static let currentFormatVersion: Int64 = 1

    /// 形式の版です。
    let formatVersion: Int64
    /// 軌跡を所有するセッションの小文字 UUID です。
    let sessionID: String
    /// 所有アカウントの fingerprint(SHA-256 の小文字16進)です。
    let accountFingerprint: String
    /// 位置のサンプルです(sequence 昇順)。
    let samples: [Sample]
    /// 位置記録の状態変化です(ordinal 昇順)。
    let events: [Event]

    /// JSON のキー名です。
    private enum CodingKeys: String, CodingKey {
        case formatVersion, sessionID, accountFingerprint, samples, events
    }

    /// 1点の位置の符号化表現です。
    struct Sample: Codable, Equatable, Sendable {
        /// セッション内の連番です。
        let sequence: Int64
        /// 観測時刻(Unix epoch からのマイクロ秒)です。
        let observedAtMicroseconds: Int64
        /// 観測時点の単調時計(ナノ秒)です。
        let monotonicNanoseconds: UInt64
        /// 緯度(度)です。
        let latitude: Double
        /// 経度(度)です。
        let longitude: Double
        /// 標高(メートル)です。
        let altitudeMeters: Double?
        /// 水平精度(メートル)です。
        let horizontalAccuracyMeters: Double
        /// 垂直精度(メートル)です。
        let verticalAccuracyMeters: Double?
        /// 対地速度(メートル毎秒)です。
        let speedMetersPerSecond: Double?
        /// 進行方向(度)です。
        let courseDegrees: Double?

        /// JSON のキー名です。
        private enum CodingKeys: String, CodingKey {
            case sequence, observedAtMicroseconds, monotonicNanoseconds, latitude, longitude
            case altitudeMeters, horizontalAccuracyMeters, verticalAccuracyMeters, speedMetersPerSecond, courseDegrees
        }
    }

    /// 1件の事象の符号化表現です。
    struct Event: Codable, Equatable, Sendable {
        /// セッション内の番号です。
        let ordinal: Int
        /// 発生時刻(Unix epoch からのマイクロ秒)です。
        let occurredAtMicroseconds: Int64
        /// 事象の種類(`ConnectionSessionLocationEventKind.rawValue`)です。
        let kind: String

        /// JSON のキー名です。
        private enum CodingKeys: String, CodingKey {
            case ordinal, occurredAtMicroseconds, kind
        }
    }
}
