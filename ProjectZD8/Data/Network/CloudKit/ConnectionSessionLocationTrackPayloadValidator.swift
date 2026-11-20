import Foundation

/// 復号した軌跡の符号化表現を検証し、Domain の軌跡へ戻します。
///
/// 検証の内容: セッション ID と fingerprint の一致、sequence と ordinal が 0 以上で重複なく昇順であること、
/// `LocationFix.init?` が成功すること、事象の種類が既知であること。版の確認は `ConnectionSessionLocationTrackPayloadCodec` が先に行います。
nonisolated struct ConnectionSessionLocationTrackPayloadValidator: Sendable {
    /// 既定の構成で作ります。
    ///
    /// 責務: 状態を持たない検証器を用意します。
    init() {}

    /// 符号化表現を検証して軌跡を返します。
    ///
    /// 責務: 所有関係・番号の並び・各要素の妥当性をすべて満たす場合だけ軌跡を組み立てます。
    /// - Parameters:
    ///   - payload: JSON から読んだ符号化表現。
    ///   - expectedSessionID: 取得を求めたセッション。
    ///   - expectedAccountFingerprint: 取得するアカウントの fingerprint。
    /// - Returns: 検証済みの軌跡。
    /// - Throws: どれか1つでも満たさない場合は `ConnectionSessionRepositoryError.integrityConflict`。
    func track(
        from payload: ConnectionSessionLocationTrackPayload,
        expectedSessionID: ConnectionSessionID,
        expectedAccountFingerprint: String
    ) throws -> ConnectionSessionLocationTrack {
        guard Self.isOwned(payload, by: expectedSessionID, accountFingerprint: expectedAccountFingerprint),
              Self.isStrictlyIncreasingNonNegative(payload.samples.map(\.sequence)),
              Self.isStrictlyIncreasingNonNegative(payload.events.map(\.ordinal)) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationTrack(
            sessionID: expectedSessionID,
            samples: try payload.samples.map(Self.makeSample),
            events: try payload.events.map(Self.makeEvent)
        )
    }

    /// 符号化表現が求めたセッションとアカウントのものかを返します。
    ///
    /// 責務: セッション ID を UUID として比べ、fingerprint を文字列として比べます。
    /// - Parameters:
    ///   - payload: 確かめる符号化表現。
    ///   - sessionID: 求めたセッション。
    ///   - accountFingerprint: 求めたアカウントの fingerprint。
    /// - Returns: 両方が一致すれば true。
    private static func isOwned(
        _ payload: ConnectionSessionLocationTrackPayload,
        by sessionID: ConnectionSessionID,
        accountFingerprint: String
    ) -> Bool {
        UUID(uuidString: payload.sessionID) == sessionID.rawValue
            && payload.accountFingerprint == accountFingerprint
    }

    /// 番号の列が 0 以上で、重複なく昇順かを返します。
    ///
    /// 責務: 先頭が 0 以上で、隣り合う番号が常に増えていることを判定します。空の列は true です。
    /// - Parameter values: 確かめる番号の列。
    /// - Returns: 条件を満たせば true。
    private static func isStrictlyIncreasingNonNegative<Value: BinaryInteger>(_ values: [Value]) -> Bool {
        guard let first = values.first, first >= 0 else {
            return values.isEmpty
        }
        return zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// サンプルの符号化表現を Domain のサンプルへ戻します。
    ///
    /// 責務: 位置の不変条件を `LocationFix.init?` で検証します。
    /// - Parameter sample: 戻す符号化表現。
    /// - Returns: Domain のサンプル。
    /// - Throws: 位置の不変条件を満たさない場合は `.integrityConflict`。
    private static func makeSample(
        _ sample: ConnectionSessionLocationTrackPayload.Sample
    ) throws -> ConnectionSessionLocationSample {
        guard let fix = LocationFix(
            latitude: sample.latitude,
            longitude: sample.longitude,
            altitudeMeters: sample.altitudeMeters,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            verticalAccuracyMeters: sample.verticalAccuracyMeters,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            courseDegrees: sample.courseDegrees,
            observedAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: sample.observedAtMicroseconds),
            monotonicNanoseconds: sample.monotonicNanoseconds
        ) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationSample(sequence: sample.sequence, fix: fix)
    }

    /// 事象の符号化表現を Domain の事象へ戻します。
    ///
    /// 責務: 種類が既知の rawValue であることを検証します。
    /// - Parameter event: 戻す符号化表現。
    /// - Returns: Domain の事象。
    /// - Throws: 未知の種類は `.integrityConflict`。
    private static func makeEvent(
        _ event: ConnectionSessionLocationTrackPayload.Event
    ) throws -> ConnectionSessionLocationEvent {
        guard let kind = ConnectionSessionLocationEventKind(rawValue: event.kind) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return ConnectionSessionLocationEvent(
            ordinal: event.ordinal,
            occurredAt: ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: event.occurredAtMicroseconds),
            kind: kind
        )
    }
}
