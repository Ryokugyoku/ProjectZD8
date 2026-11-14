import Foundation
import GRDB
@testable import ProjectZD8

/// 取得記録の検証対象と、メモリ上のGRDB・フェイクの保存先・手動時計をまとめたテスト部品です。
///
/// セッションとmanifestは常にメモリ上のGRDBへ保存します。チャンク・区間・欠損の保存先は
/// `.fake` ではメモリ上のスパイ、`.grdb` では同じQueueのGRDB Repositoryです(チャンクはスパイ経由)。
@MainActor
final class ConnectionSessionAcquisitionRecorderFixture {
    /// チャンク・区間・欠損の保存先の種類です。
    enum Storage {
        /// メモリ上のスパイへ保存します。
        case fake
        /// メモリ上のGRDBへ保存します。
        case grdb
    }

    /// 取得対象の2PIDです(manifest順)。
    static let definitions = [0x0C, 0x0D].map { pid in
        OBDPIDDefinition(
            service: 0x01, pid: pid, nameKey: "test.pid", requiredByteCount: 1, formula: "A",
            unit: "unit", minimumValue: 0, maximumValue: 255, sourceURI: "test://pid", revision: 1
        )
    }
    /// 時計の起点となる実時刻です。
    static let startDate = Date(timeIntervalSince1970: 1_000)

    /// 共有するメモリ上のDB Queueです。
    let queue: DatabaseQueue
    /// 親セッションとRawの読み戻し先です。
    let sessions: GRDBConnectionSessionRepository
    /// manifestとbatch証拠の読み戻し先です。
    let acquisition: GRDBConnectionSessionAcquisitionRepository
    /// 保存済みの未終了セッションIDです。
    let sessionID: ConnectionSessionID
    /// チャンクのcommitを記録するスパイです。
    let chunks: AcquisitionChunkRepositorySpy
    /// 区間の保存先です。
    let segments: any ConnectionSessionSegmentRepository
    /// 欠損の保存先です。
    let gaps: any ConnectionSessionGapRepository
    /// 単調時計です。
    let clock: SettableMonotonicClock
    /// 実時刻clockです。
    let dates: ManualDateClock
    /// 性能eventのスパイです。
    let performance: AcquisitionPerformanceEventSpy
    /// 検証対象の取得記録です。
    let recorder: ConnectionSessionAcquisitionRecorder

    /// 保存先の種類と失敗指定を固定して生成します。
    ///
    /// 責務: 未終了セッションを保存し、指定どおりの保存先と時計を取得記録へ注入します。
    /// - Parameters:
    ///   - storage: チャンク・区間・欠損の保存先の種類。
    ///   - failingCommits: 失敗させるcommitの回(0始まり)。
    ///   - gapRepository: `.fake` で使う欠損Repository。`nil` なら成功するスパイ。
    ///   - segmentRepository: `.fake` で使う区間Repository。`nil` なら成功するスパイ。
    ///   - nextRawSequence: 次の記録順序。`nil` なら保存済みRawの件数。
    ///   - exposesSession: 現在のセッションIDを返すかどうか。
    /// - Throws: DB作成・Migration・セッション保存の失敗。
    init(
        storage: Storage = .fake,
        failingCommits: Set<Int> = [],
        gapRepository: AcquisitionGapRepositorySpy? = nil,
        segmentRepository: AcquisitionSegmentRepositorySpy? = nil,
        nextRawSequence: Int64? = nil,
        exposesSession: Bool = true
    ) throws {
        queue = try DatabaseQueue()
        sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let sessionID = ConnectionSessionID()
        self.sessionID = sessionID
        try sessions.save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 1)))
        let isGRDB = storage == .grdb
        chunks = AcquisitionChunkRepositorySpy(
            base: isGRDB ? try GRDBConnectionSessionAcquisitionChunkRepository(databaseQueue: queue) : nil,
            failingAttempts: failingCommits
        )
        segments = isGRDB ? try GRDBConnectionSessionSegmentRepository(databaseQueue: queue)
            : segmentRepository ?? AcquisitionSegmentRepositorySpy()
        gaps = isGRDB ? try GRDBConnectionSessionGapRepository(databaseQueue: queue) : gapRepository ?? AcquisitionGapRepositorySpy()
        clock = SettableMonotonicClock(initialNanoseconds: 5_000)
        dates = ManualDateClock(Self.startDate)
        performance = AcquisitionPerformanceEventSpy()
        recorder = Self.makeRecorder(
            acquisition: acquisition, chunks: chunks, segments: segments, gaps: gaps,
            nextRawSequence: Self.nextRawSequence(sessions: sessions, fixed: nextRawSequence),
            activeSessionID: { exposesSession ? sessionID : nil },
            clock: clock, dates: dates, performance: performance
        )
    }

    /// 2PIDの取得記録を開始します。
    ///
    /// 責務: 固定の2PIDと収集有効capability、manifest順の要求列で `start` を呼びます。
    /// - Parameter generation: 世代。
    /// - Throws: 取得記録の開始失敗。
    func start(generation: UInt = 1) async throws {
        let requests = Self.definitions.map { OBDPIDRequest(service: $0.service, pid: $0.pid) }
        try await recorder.start(
            LiveTelemetryAcquisitionStartInput(
                generation: generation,
                definitions: Self.definitions,
                capabilities: requests.map { .init(request: $0, support: .supported, isCollectionEnabled: true) },
                orderedRequests: requests
            )
        )
    }

    /// 1周回の開始を記録します。
    ///
    /// 責務: 現在の実時刻を開始日時にして、指定PIDの要求列で `beginRound` を呼びます。
    /// - Parameters:
    ///   - ordinal: batch番号。周回番号にも使います。
    ///   - pids: 周回で送る Service 01 のPID。
    ///   - generation: 世代。
    /// - Throws: 取得記録の失敗。
    func beginRound(_ ordinal: Int64, pids: [UInt8] = [0x0C], generation: UInt = 1) async throws {
        try await recorder.beginRound(
            LiveTelemetryAcquisitionRoundInput(
                generation: generation,
                batchOrdinal: ordinal,
                policyTick: UInt(ordinal),
                startedAt: dates.now(),
                requests: pids.map { OBDPIDRequest(service: 0x01, pid: $0) }
            )
        )
    }

    /// 要求1件の結果を記録します。
    ///
    /// 責務: 正応答なら値の評価を `decodedValid`、それ以外は `notEvaluated` を既定にして `record` を呼びます。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - requestOrdinal: 周回内の要求順。
    ///   - pid: Service 01 のPID。
    ///   - outcome: Transport結果。
    ///   - valueOutcome: 値の評価。`nil` なら結果から既定値を選びます。
    ///   - elapsedNanoseconds: 要求の経過。
    ///   - generation: 世代。
    /// - Throws: 取得記録の失敗。
    func record(
        _ ordinal: Int64,
        _ requestOrdinal: Int,
        pid: UInt8 = 0x0C,
        _ outcome: OBDPIDRequestTransportOutcome,
        valueOutcome: PIDRequestValueOutcome? = nil,
        elapsedNanoseconds: UInt64 = 100,
        generation: UInt = 1
    ) async throws {
        let isResponded = if case .responded = outcome { true } else { false }
        try await recorder.record(
            LiveTelemetryRequestResult(
                generation: generation,
                batchOrdinal: ordinal,
                requestOrdinal: requestOrdinal,
                request: OBDPIDRequest(service: 0x01, pid: pid),
                outcome: outcome,
                valueOutcome: valueOutcome ?? (isResponded ? .decodedValid : .notEvaluated),
                elapsedNanoseconds: elapsedNanoseconds
            )
        )
    }

    /// 1周回の終了を記録します。
    ///
    /// 責務: `finishRound` を呼びます。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - generation: 世代。
    /// - Throws: 取得記録の失敗。
    func finishRound(_ ordinal: Int64, generation: UInt = 1) async throws {
        try await recorder.finishRound(generation: generation, batchOrdinal: ordinal)
    }

    /// PID 0x0C だけの周回を、指定payloadの正応答1件で開始から終了まで記録します。
    ///
    /// 責務: Raw 1件と終端済みbatch 1件をバッファへ積む周回を記録します。
    /// - Parameters:
    ///   - ordinal: batch番号。
    ///   - payload: 正応答の1バイト。
    ///   - generation: 世代。
    /// - Throws: 取得記録の失敗。
    func respondedRound(_ ordinal: Int64, payload: UInt8, generation: UInt = 1) async throws {
        try await beginRound(ordinal, generation: generation)
        try await record(ordinal, 0, .responded([payload]), generation: generation)
        try await finishRound(ordinal, generation: generation)
    }

    /// 保存済みのRawを返します。
    ///
    /// 責務: 既定セッションのRawを連番順に読み戻します。
    /// - Returns: 保存済みのRaw。
    /// - Throws: 読込失敗。
    func storedRaws() throws -> [ConnectionSessionRawLogEntry] {
        try sessions.entries(for: sessionID)
    }

    /// 取得記録を組み立てます。
    ///
    /// 責務: 保存先・時計・方針・性能eventを取得記録へ注入します。
    /// - Returns: 取得記録。
    private static func makeRecorder(
        acquisition: GRDBConnectionSessionAcquisitionRepository,
        chunks: AcquisitionChunkRepositorySpy,
        segments: any ConnectionSessionSegmentRepository,
        gaps: any ConnectionSessionGapRepository,
        nextRawSequence: @escaping @Sendable (ConnectionSessionID) async throws -> Int64,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        clock: SettableMonotonicClock,
        dates: ManualDateClock,
        performance: AcquisitionPerformanceEventSpy
    ) -> ConnectionSessionAcquisitionRecorder {
        ConnectionSessionAcquisitionRecorder(
            createManifest: CreateConnectionSessionAcquisitionManifestUseCase(
                acquisitionRepository: acquisition,
                evidencePort: FixedAcquisitionRuntimeEvidencePort(),
                now: { Date(timeIntervalSince1970: 2) }
            ),
            chunkRepository: chunks,
            segmentRepository: segments,
            gapRepository: gaps,
            nextRawSequence: nextRawSequence,
            activeSessionID: activeSessionID,
            versions: AcquisitionManifestVersions(
                manifestVersion: 1, pollingPolicyVersion: 1, modelInputManifestVersion: 1, formulaCanonicalizationVersion: 1
            ),
            now: { dates.now() },
            clock: clock,
            performanceEvents: performance
        )
    }

    /// 次の記録順序を返す処理を作ります。
    ///
    /// 責務: 固定値の指定があればそれを、無ければ保存済みRawの件数を返す処理を返します。
    /// - Parameters:
    ///   - sessions: 保存済みRawの件数を数えるRepository。
    ///   - fixed: 固定の次の記録順序。
    /// - Returns: 次の記録順序を返す処理。
    private static func nextRawSequence(
        sessions: GRDBConnectionSessionRepository,
        fixed: Int64?
    ) -> @Sendable (ConnectionSessionID) async throws -> Int64 {
        { sessionID in
            if let fixed { return fixed }
            return try await MainActor.run { Int64(try sessions.entryCount(for: sessionID)) }
        }
    }
}
