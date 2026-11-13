import Foundation
import GRDB

/// `session_samples` テーブルの1行です。追記のみで更新しません。
nonisolated struct SessionSampleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "session_samples"

    var sessionID: String
    var sequence: Int64
    var tick: Int
    var elapsedMicroseconds: Int64
    var service: Int
    var pid: Int
    var outcome: Int
    var payload: Data

    /// 責務: サンプルエンティティから行を生成します。
    init(_ sample: SessionSample, sessionID: SessionID) {
        self.sessionID = sessionID.rowID
        sequence = sample.sequence
        tick = sample.tick
        elapsedMicroseconds = sample.elapsedMicroseconds
        service = Int(sample.request.service)
        pid = Int(sample.request.pid)
        outcome = sample.outcome.rawValue
        payload = sample.payload
    }

    /// 責務: 行をサンプルエンティティへ変換します。不正な値は `StoreError.ioFailure` を投げます。
    func entity() throws -> SessionSample {
        guard
            let service = UInt8(exactly: service),
            let pid = UInt8(exactly: pid),
            let outcome = SampleOutcome(rawValue: outcome)
        else { throw StoreError.ioFailure }
        return SessionSample(
            sequence: sequence,
            tick: tick,
            elapsedMicroseconds: elapsedMicroseconds,
            request: OBDPIDRequest(service: service, pid: pid),
            outcome: outcome,
            payload: payload
        )
    }
}
