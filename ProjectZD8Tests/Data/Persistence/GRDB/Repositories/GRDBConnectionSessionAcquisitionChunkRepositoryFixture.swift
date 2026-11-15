import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得チャンクRepositoryのテストが共有する、同一インメモリQueue上の親集約と値生成の部品です。
struct GRDBConnectionSessionAcquisitionChunkRepositoryFixture {
    /// 全Repositoryが共有するインメモリDB Queueです。
    let queue: DatabaseQueue
    /// 親セッションとRawの読み戻し先です。
    let sessions: GRDBConnectionSessionRepository
    /// manifestとbatch証拠の読み戻し先です。
    let acquisition: GRDBConnectionSessionAcquisitionRepository
    /// セグメント開始の保存先です。
    let segments: GRDBConnectionSessionSegmentRepository
    /// 検証対象の取得チャンクRepositoryです。
    let repository: GRDBConnectionSessionAcquisitionChunkRepository
    /// 保存済みの未終了セッションIDです。
    let sessionID: ConnectionSessionID

    /// 未終了セッションと、指定に応じて確定manifest・開始済みセグメントを用意します。
    ///
    /// 責務: チャンク保存の前提となる親集約を同一Queueへ保存します。
    /// - Parameters:
    ///   - savesManifest: 確定manifestを保存するか。
    ///   - startedSegmentOrdinals: 開始を保存するセグメント番号。
    /// - Throws: DB作成・Migration・前提データ保存の失敗。
    init(savesManifest: Bool = true, startedSegmentOrdinals: [Int] = [0]) throws {
        queue = try DatabaseQueue()
        sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        segments = try GRDBConnectionSessionSegmentRepository(databaseQueue: queue)
        repository = try GRDBConnectionSessionAcquisitionChunkRepository(databaseQueue: queue)
        sessionID = ConnectionSessionID()
        try sessions.save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1)))
        if savesManifest {
            try acquisition.saveStartOnce(manifest: Self.manifest(), startedAt: Date(timeIntervalSince1970: 2), for: sessionID)
        }
        for ordinal in startedSegmentOrdinals {
            try segments.beginSegment(Self.segment(ordinal: ordinal), for: sessionID)
        }
    }

    /// 終了済みの別セッションを保存してIDを返します。
    ///
    /// 責務: 終了済みセッションへのcommitを拒否することを確かめる親セッションを1件追加します。
    /// - Returns: 保存済みの終了済みセッションID。
    /// - Throws: セッション保存の失敗。
    func makeEndedSession() throws -> ConnectionSessionID {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1))
        session.endedAt = Date(timeIntervalSince1970: 50)
        session.endReason = .userDisconnected
        try sessions.save(session)
        return session.id
    }

    /// 既定セッションのチャンクを生成します。
    ///
    /// 責務: 既定セッションIDへRawとbatchを束ねたチャンクを返します。
    /// - Parameters:
    ///   - raws: チャンクに含めるRaw。
    ///   - batches: チャンクに含めるbatch。
    /// - Returns: 既定セッションのチャンク。
    func chunk(raws: [ConnectionSessionRawLogEntry], batches: [AcquisitionBatchEvidence] = []) -> ConnectionSessionAcquisitionChunk {
        ConnectionSessionAcquisitionChunk(sessionID: sessionID, rawEntries: raws, batches: batches)
    }

    /// Raw・batch・requestの全行数を返します。
    ///
    /// 責務: セッションを問わず3表の行数を型付きクエリで数えます。
    /// - Returns: (Raw数, batch数, request数)。
    /// - Throws: SQLite読込失敗。
    func rowCounts() throws -> RowCounts {
        try queue.read { database in
            RowCounts(
                raws: try ConnectionSessionRawLogRecord.fetchCount(database),
                batches: try ConnectionSessionAcquisitionBatchRecord.fetchCount(database),
                requests: try ConnectionSessionAcquisitionPIDRequestRecord.fetchCount(database)
            )
        }
    }

    /// commitが指定エラーで失敗し、どの表の行数も変えないことを検証します。
    ///
    /// 責務: エラーの型とcaseを確かめ、失敗したチャンクの行が1行も残らないことを確認します。
    /// - Parameters:
    ///   - chunk: 失敗するはずのチャンク。
    ///   - expected: 期待する失敗理由。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Throws: 行数の読込失敗。
    func assertCommitRejected(
        _ chunk: ConnectionSessionAcquisitionChunk,
        with expected: ConnectionSessionAcquisitionChunkRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let before = try rowCounts()
        XCTAssertThrowsError(try repository.commit(chunk), file: file, line: line) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionChunkRepositoryError, expected, file: file, line: line)
        }
        XCTAssertEqual(try rowCounts(), before, file: file, line: line)
    }

    /// 時刻情報を持つRawを生成します。
    ///
    /// 責務: 連番ごとに異なる実時刻・単調時計・payloadを持つRawを、指定項目だけ差し替えて返します。
    /// - Parameters:
    ///   - sequence: セッション内連番。
    ///   - segment: 所属セグメント番号。
    ///   - omitsMonotonic: 単調時計ナノ秒を持たせない場合は `true`。
    /// - Returns: Raw entry。
    static func raw(sequence: Int64, segment: Int? = 0, omitsMonotonic: Bool = false) -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: Date(timeIntervalSince1970: 100 + Double(sequence)),
            batchElapsedNanoseconds: 500 + UInt64(sequence),
            service: 1,
            pid: 12,
            payload: [UInt8(truncatingIfNeeded: sequence), 0x40],
            monotonicNanoseconds: omitsMonotonic ? nil : 7_000_000_000 + UInt64(sequence) * 1_000,
            segmentOrdinal: segment
        )
    }

    /// responded requestとtimedOut requestを持つ終端batchを生成します。
    ///
    /// 責務: 先頭PIDが指定Rawへ応答し2番目のPIDが応答しなかったbatch証拠を返します。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - respondedSequence: responded requestが参照するRaw連番。
    /// - Returns: completedのbatch証拠。
    /// - Throws: batch証拠の不変条件違反。
    static func terminalBatch(ordinal: Int64, respondedSequence: Int64) throws -> AcquisitionBatchEvidence {
        let responded = try PIDRequestEvidence(
            requestOrdinal: 0, manifestPIDOrdinal: 0, dispatchState: .terminal, transportOutcome: .responded,
            valueOutcome: .decodedValid, rawSequence: respondedSequence, elapsedNanoseconds: 200, reasonCode: nil
        )
        let timedOut = try PIDRequestEvidence(
            requestOrdinal: 1, manifestPIDOrdinal: 1, dispatchState: .terminal, transportOutcome: .timedOut,
            valueOutcome: .notEvaluated, rawSequence: nil, elapsedNanoseconds: 300, reasonCode: nil
        )
        return try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: ordinal),
            generation: 1,
            policyTick: UInt(ordinal),
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 100 + Double(ordinal)),
            completionState: .completed,
            completedAt: Date(timeIntervalSince1970: 101 + Double(ordinal)),
            failure: nil,
            requests: [responded, timedOut]
        )
    }

    /// 終端状態でない未確定batchを生成します。
    ///
    /// 責務: completionStateがnilのbatch証拠を返します。
    /// - Parameter ordinal: batch番号。
    /// - Returns: 未確定のbatch証拠。
    /// - Throws: batch証拠の不変条件違反。
    static func openBatch(ordinal: Int64) throws -> AcquisitionBatchEvidence {
        let selected = try PIDRequestEvidence(
            requestOrdinal: 0, manifestPIDOrdinal: 0, dispatchState: .selectedOnly, transportOutcome: nil,
            valueOutcome: .notEvaluated, rawSequence: nil, elapsedNanoseconds: nil, reasonCode: nil
        )
        return try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: ordinal),
            generation: 1,
            policyTick: UInt(ordinal),
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 100),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: [selected]
        )
    }

    /// 開始時点のセグメントを生成します。
    ///
    /// 責務: 指定番号の未終了セグメントを返します。
    /// - Parameter ordinal: セグメント番号。
    /// - Returns: 未終了のセグメント。
    static func segment(ordinal: Int) -> ConnectionSessionSegment {
        ConnectionSessionSegment(
            segmentOrdinal: ordinal, startReason: ordinal == 0 ? .initial : .reconnected, acquisitionMode: .pidPolling,
            startedAt: Date(timeIntervalSince1970: 3 + Double(ordinal)), monotonicAnchorNanoseconds: 5, firstSequence: 0
        )
    }

    /// 2PIDの完全manifestを生成します。
    ///
    /// 責務: batch requestが参照できる連続manifest PID集合を返します。
    /// - Returns: 2件の完全PID snapshotを持つmanifest。
    /// - Throws: manifestの不変条件違反。
    static func manifest() throws -> ConnectionSessionAcquisitionManifest {
        let requests = [OBDPIDRequest(service: 1, pid: 12), OBDPIDRequest(service: 1, pid: 13)]
        let definitions = try requests.map { request in
            try AcquisitionPIDDefinitionSnapshot(
                request: request,
                capabilitySupport: .supported,
                isCollectionEnabled: true,
                definitionRevision: 1,
                requiredByteCount: 2,
                definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "A"),
                unit: "unit",
                validityRange: .notDeclared
            )
        }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "1", buildVersion: "1"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: requests),
            pidDefinitions: definitions,
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }

    /// 取得チャンクが書く3表の行数です。
    struct RowCounts: Equatable {
        /// Raw行数です。
        let raws: Int
        /// batch行数です。
        let batches: Int
        /// request行数です。
        let requests: Int
    }
}
