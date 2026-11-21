import Foundation

/// 軌跡と、iCloud の Asset に入れるバイト列(LZFSE で圧縮した JSON)を相互に変換します。
///
/// 形式の版 1 は「`JSONEncoder`(`.sortedKeys, .withoutEscapingSlashes`)で符号化した JSON を
/// `NSData.compressed(using: .lzfse)` で圧縮したバイト列」です。時刻はマイクロ秒の Int64、事象の種類は rawValue です。
nonisolated struct ConnectionSessionLocationTrackPayloadCodec: Sendable {
    /// 復号した内容を検証して軌跡へ戻す規則です。
    private let validator = ConnectionSessionLocationTrackPayloadValidator()

    /// 版だけを先に読むための最小の JSON 表現です。
    private struct FormatHeader: Decodable {
        /// 形式の版です。
        let formatVersion: Int64
    }

    /// 既定の構成で作ります。
    ///
    /// 責務: 状態を持たない Codec を用意します。
    init() {}

    /// 軌跡を、Asset に入れる圧縮済みのバイト列へ符号化します。
    ///
    /// 責務: 1件の軌跡を版 1 の JSON にし、LZFSE で圧縮します。
    /// - Parameters:
    ///   - track: 符号化する軌跡。
    ///   - accountFingerprint: 所有アカウントの fingerprint。
    /// - Returns: 圧縮後のバイト列。
    /// - Throws: 空の軌跡は `ConnectionSessionRepositoryError.invalidState`。時刻を表せない場合は `.integrityConflict`。
    func encode(_ track: ConnectionSessionLocationTrack, accountFingerprint: String) throws -> Data {
        guard track.isEmpty == false else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let payload = ConnectionSessionLocationTrackPayload(
            formatVersion: ConnectionSessionLocationTrackPayload.currentFormatVersion,
            sessionID: track.sessionID.rawValue.uuidString.lowercased(),
            accountFingerprint: accountFingerprint,
            samples: try track.samples.map(Self.makeSamplePayload),
            events: try track.events.map(Self.makeEventPayload)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(payload)
        return try (json as NSData).compressed(using: .lzfse) as Data
    }

    /// 圧縮済みのバイト列を伸長し、検証してから軌跡へ戻します。
    ///
    /// 責務: 版を先に確かめ、内容がセッション・アカウント・番号・位置の規則を満たす場合だけ軌跡を返します。
    /// - Parameters:
    ///   - data: Asset から読んだ圧縮済みのバイト列。
    ///   - expectedSessionID: 取得を求めたセッション。
    ///   - expectedAccountFingerprint: 取得するアカウントの fingerprint。
    /// - Returns: 検証済みの軌跡。
    /// - Throws: 版が新しすぎる場合は `ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat`。
    ///   伸長・JSON の読み取り・検証の失敗は `ConnectionSessionRepositoryError.integrityConflict`。
    func decode(
        _ data: Data,
        expectedSessionID: ConnectionSessionID,
        expectedAccountFingerprint: String
    ) throws -> ConnectionSessionLocationTrack {
        let json = try Self.decompress(data)
        let version = try Self.decodeJSON(FormatHeader.self, from: json).formatVersion
        guard version <= ConnectionSessionLocationTrackPayload.currentFormatVersion else {
            throw ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: version)
        }
        guard version == ConnectionSessionLocationTrackPayload.currentFormatVersion else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        let payload = try Self.decodeJSON(ConnectionSessionLocationTrackPayload.self, from: json)
        return try validator.track(
            from: payload,
            expectedSessionID: expectedSessionID,
            expectedAccountFingerprint: expectedAccountFingerprint
        )
    }

    /// 位置のサンプルを符号化表現へ変換します。
    ///
    /// 責務: 観測時刻をマイクロ秒にし、ほかの値はそのまま写します。
    /// - Parameter sample: 変換するサンプル。
    /// - Returns: 符号化表現。
    /// - Throws: 時刻を Int64 のマイクロ秒で表せない場合は `.integrityConflict`。
    private static func makeSamplePayload(
        _ sample: ConnectionSessionLocationSample
    ) throws -> ConnectionSessionLocationTrackPayload.Sample {
        let fix = sample.fix
        return ConnectionSessionLocationTrackPayload.Sample(
            sequence: sample.sequence,
            observedAtMicroseconds: try ConnectionSessionMicrosecondTimestamp.microseconds(for: fix.observedAt),
            monotonicNanoseconds: fix.monotonicNanoseconds,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitudeMeters: fix.altitudeMeters,
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
            verticalAccuracyMeters: fix.verticalAccuracyMeters,
            speedMetersPerSecond: fix.speedMetersPerSecond,
            courseDegrees: fix.courseDegrees
        )
    }

    /// 事象を符号化表現へ変換します。
    ///
    /// 責務: 発生時刻をマイクロ秒にし、種類を rawValue にします。
    /// - Parameter event: 変換する事象。
    /// - Returns: 符号化表現。
    /// - Throws: 時刻を Int64 のマイクロ秒で表せない場合は `.integrityConflict`。
    private static func makeEventPayload(
        _ event: ConnectionSessionLocationEvent
    ) throws -> ConnectionSessionLocationTrackPayload.Event {
        ConnectionSessionLocationTrackPayload.Event(
            ordinal: event.ordinal,
            occurredAtMicroseconds: try ConnectionSessionMicrosecondTimestamp.microseconds(for: event.occurredAt),
            kind: event.kind.rawValue
        )
    }

    /// LZFSE で圧縮されたバイト列を伸長します。
    ///
    /// 責務: 伸長の失敗を整合性の失敗として表します。
    /// - Parameter data: 圧縮済みのバイト列。
    /// - Returns: 伸長後の JSON バイト列。
    /// - Throws: 伸長できない場合は `.integrityConflict`。
    private static func decompress(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
    }

    /// JSON バイト列を指定の型へ読み取ります。
    ///
    /// 責務: JSON として壊れている・形が合わない場合を整合性の失敗として表します。
    /// - Parameters:
    ///   - type: 読み取る型。
    ///   - json: JSON バイト列。
    /// - Returns: 読み取った値。
    /// - Throws: 読み取れない場合は `.integrityConflict`。
    private static func decodeJSON<Value: Decodable>(_ type: Value.Type, from json: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: json)
        } catch {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
    }
}
