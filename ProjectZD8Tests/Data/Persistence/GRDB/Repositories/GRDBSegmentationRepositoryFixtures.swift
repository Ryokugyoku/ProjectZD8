import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// セグメント・欠損・CANフレームRepositoryのテストが共有する、同一Queue上のRepository群と値生成の部品です。
struct GRDBSegmentationRepositoryFixtures {
    /// 3つのRepositoryが共有するインメモリDB Queueです。
    let queue: DatabaseQueue
    /// 親セッションを保存するRepositoryです。
    let sessions: GRDBConnectionSessionRepository
    /// 検証対象のセグメントRepositoryです。
    let segments: GRDBConnectionSessionSegmentRepository
    /// 検証対象の欠損Repositoryです。
    let gaps: GRDBConnectionSessionGapRepository
    /// 検証対象のCANフレームRepositoryです。
    let frames: GRDBConnectionSessionCANFrameRepository
    /// 保存済みの既定の親セッションIDです。
    let sessionID: ConnectionSessionID

    /// 空のDBへ3つのRepositoryと既定の親セッションを用意します。
    ///
    /// 責務: 同一Queue上にRepository群を作り、既定の親セッション1件を保存します。
    /// - Throws: DB作成・Migration・セッション保存の失敗。
    init() throws {
        queue = try DatabaseQueue()
        sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        segments = try GRDBConnectionSessionSegmentRepository(databaseQueue: queue)
        gaps = try GRDBConnectionSessionGapRepository(databaseQueue: queue)
        frames = try GRDBConnectionSessionCANFrameRepository(databaseQueue: queue)
        sessionID = ConnectionSessionID()
        try sessions.save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100)))
    }

    /// 別の親セッションを保存してIDを返します。
    ///
    /// 責務: 他セッションの行が混ざらないことを確かめるための親セッションを1件追加します。
    /// - Returns: 保存済みの別セッションID。
    /// - Throws: セッション保存の失敗。
    func makeOtherSession() throws -> ConnectionSessionID {
        let id = ConnectionSessionID()
        try sessions.save(ConnectionSession(id: id, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100)))
        return id
    }

    /// 未終了のセグメント値を生成します。
    ///
    /// 責務: 既定値を持つ1件の未終了セグメントを、指定項目だけ差し替えて返します。
    /// - Parameters:
    ///   - ordinal: セグメント番号。
    ///   - startReason: 開始理由。
    ///   - mode: 取得モード。
    ///   - startedAt: 開始時刻。
    ///   - anchor: 単調時計アンカー。
    ///   - firstSequence: 先頭記録順序。
    /// - Returns: 未終了のセグメント。
    static func segment(
        ordinal: Int = 0,
        startReason: ConnectionSessionSegmentStartReason = .initial,
        mode: ConnectionSessionAcquisitionMode = .pidPolling,
        startedAt: Date = Date(timeIntervalSince1970: 1_000),
        anchor: UInt64 = 5,
        firstSequence: Int64 = 0
    ) -> ConnectionSessionSegment {
        ConnectionSessionSegment(
            segmentOrdinal: ordinal, startReason: startReason, acquisitionMode: mode, startedAt: startedAt,
            monotonicAnchorNanoseconds: anchor, firstSequence: firstSequence
        )
    }

    /// 欠損値を生成します。
    ///
    /// 責務: 既定値を持つ1件の欠損を、指定項目だけ差し替えて返します。
    /// - Parameters:
    ///   - ordinal: 欠損番号。
    ///   - preceding: 直前セグメント番号。
    ///   - following: 直後セグメント番号。
    ///   - startedAt: 開始時刻。
    ///   - endedAt: 終了時刻。
    ///   - cause: 原因。
    /// - Returns: 欠損。
    static func gap(
        ordinal: Int = 0,
        preceding: Int = 0,
        following: Int? = nil,
        startedAt: Date = Date(timeIntervalSince1970: 2_000),
        endedAt: Date? = nil,
        cause: ConnectionSessionGapCause = .linkLost
    ) -> ConnectionSessionGap {
        ConnectionSessionGap(
            gapOrdinal: ordinal, precedingSegmentOrdinal: preceding, followingSegmentOrdinal: following,
            startedAt: startedAt, endedAt: endedAt, cause: cause
        )
    }

    /// CANフレーム値を生成します。
    ///
    /// 責務: 既定値を持つ1件のフレームを、指定項目だけ差し替えて返します。
    /// - Parameters:
    ///   - sequence: 記録順序。
    ///   - segment: 所属セグメント番号。
    ///   - identifier: CAN識別子。
    ///   - payload: payload。
    ///   - monotonic: 単調時計ナノ秒。
    /// - Returns: CANフレーム。
    static func frame(
        sequence: Int64,
        segment: Int = 0,
        identifier: UInt32 = 0x123,
        payload: [UInt8] = [0x01],
        monotonic: UInt64 = 10
    ) -> CANFrameObservation {
        CANFrameObservation(
            sequence: sequence, segmentOrdinal: segment, receivedAt: Date(timeIntervalSince1970: 3_000),
            monotonicNanoseconds: monotonic, canIdentifier: identifier, payload: payload
        )
    }

    /// 3表の全行数を返します。
    ///
    /// 責務: セッションを問わずセグメント・欠損・フレームの行数を数えます。
    /// - Returns: (セグメント数, 欠損数, フレーム数)。
    /// - Throws: SQLite読込失敗。
    func rowCounts() throws -> (segments: Int, gaps: Int, frames: Int) {
        try queue.read { database in
            (
                try ConnectionSessionSegmentRecord.fetchCount(database),
                try ConnectionSessionGapRecord.fetchCount(database),
                try ConnectionSessionCANFrameRecord.fetchCount(database)
            )
        }
    }
}
