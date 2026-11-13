import Foundation

/// リアルタイム表示が取得中に受け取る出来事です。
nonisolated enum LiveTelemetryEvent: Sendable {
    /// 記録が始まりました。
    case sessionStarted(Session)
    /// 1ティック分の値が届きました。
    case tick(Tick)
    /// 記録が終わりました。
    case sessionEnded(SessionEndReason)

    /// 開始したセッションの情報です。
    nonisolated struct Session: Equatable, Sendable {
        let sessionID: SessionID
        let adapterName: String
        /// 表示対象にするPID(収集有効のもの)です。
        let channels: [ChannelSpec]
    }

    /// 1つの表示チャンネルの静的な情報です。
    nonisolated struct ChannelSpec: Equatable, Sendable {
        let request: OBDPIDRequest
        /// セッション内の並び順です。
        let ordinal: Int
        /// 名称のローカライズキーです。
        let nameKey: String
        let unit: String
        let minimumValue: Double?
        let maximumValue: Double?
    }

    /// 1ティック分の値です。
    nonisolated struct Tick: Equatable, Sendable {
        let elapsedMicroseconds: Int64
        let readings: [TickReading]
        let sampleCount: Int
        let respondedCount: Int
        let distanceKilometers: Double?
    }

    /// 1件のPIDの値です。
    nonisolated struct TickReading: Equatable, Sendable {
        let request: OBDPIDRequest
        let reading: Reading
    }

    /// 値の状態です。
    nonisolated enum Reading: Equatable, Sendable {
        case value(Double)
        case outOfRange(Double)
        case decodeFailed
        case noResponse(SampleOutcome)
    }
}
