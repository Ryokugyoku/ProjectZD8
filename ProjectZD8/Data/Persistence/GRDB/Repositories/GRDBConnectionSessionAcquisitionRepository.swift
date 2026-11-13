import Foundation
import GRDB
import OSLog

/// GRDBへsession取得manifestとappend-only Raw境界を原子的に保存します。
final class GRDBConnectionSessionAcquisitionRepository: ConnectionSessionAcquisitionRepository, ConnectionSessionAcquisitionBatchRepository, ConnectionSessionAcquisitionTerminationRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// 匿名取得性能eventの通知先です。
    private let performanceEvents: any AcquisitionPerformanceEventPort
    /// GRDB詳細を内向き診断へ保持するloggerです。
    private let logger = Logger(subsystem: "ProjectZD8", category: "AcquisitionEvidencePersistence")

    /// 指定DB Queueへ全forward-only migrationを適用して生成します。
    ///
    /// 責務: SQLite接続を取得証拠schema利用可能状態へ移行してrepositoryを生成します。
    /// - Parameters:
    ///   - databaseQueue: 取得証拠を保存するDB Queue。
    ///   - performanceEvents: Queue待機とtransaction区間を通知する匿名計測境界。
    /// - Throws: migration失敗を `ConnectionSessionAcquisitionRepositoryError.unavailable` として返します。
    init(
        databaseQueue: DatabaseQueue,
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort()
    ) throws {
        self.databaseQueue = databaseQueue
        self.performanceEvents = performanceEvents
        do {
            try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
        } catch {
            logger.error("取得証拠migration失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 未登録sessionへmanifestと開始境界を1回だけ保存します。
    ///
    /// 責務: canonical manifest aggregateと開始境界を1回のSQLite transactionで保存し完全readback時だけ確定します。
    /// - Parameters:
    ///   - manifest: 全semantic fieldを持つ新規取得manifest。
    ///   - startedAt: 最初のRaw要求直前の開始境界時刻。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 重複、競合、または保存先失敗を区別する `ConnectionSessionAcquisitionRepositoryError`。
    func saveStartOnce(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            let expected = try canonicalStart(manifest: manifest, startedAt: startedAt)
            try measuredWrite(operation: .manifestPersistence) { database in
                if let stored = try readCanonicalStart(sessionID: sessionID, database: database) {
                    guard stored == expected else {
                        throw ConnectionSessionAcquisitionRepositoryError.conflict
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.duplicate
                }
                let key = databaseKey(for: sessionID)
                guard try String.fetchOne(
                    database,
                    sql: "SELECT id FROM connection_sessions WHERE id = ?",
                    arguments: [key]
                ) != nil else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
                try insertStart(expected, sessionID: key, database: database)
                guard try readCanonicalStart(sessionID: sessionID, database: database) == expected else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得開始証拠保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 開始済みsessionへ終了境界を1回だけ追記します。
    ///
    /// 責務: canonical終了境界を開始境界との時系列検証後に1回のSQLite transactionで追記します。
    /// - Parameters:
    ///   - endedAt: Raw取得終了境界時刻。
    ///   - reason: Raw取得停止の直接原因。
    ///   - sessionID: 親接続セッションID。
    /// - Throws: 重複、競合、開始欠落、時系列違反、または保存先失敗を区別するrepository error。
    func appendEnd(
        at endedAt: Date,
        reason: ConnectionSessionEndReason,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            let endedMicroseconds = try canonicalMicroseconds(for: endedAt)
            try measuredWrite(operation: .sessionTerminationPersistence) { database in
                let boundaries = try boundaryRecords(sessionID: sessionID, database: database)
                guard let started = boundaries.first(where: { $0.eventKind == "started" }) else {
                    if boundaries.isEmpty {
                        throw ConnectionSessionAcquisitionRepositoryError.startEvidenceMissing
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
                guard boundaries.filter({ $0.eventKind == "started" }).count == 1,
                      started.endReason == nil else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
                if let existingEnd = boundaries.first(where: { $0.eventKind == "ended" }) {
                    guard boundaries.filter({ $0.eventKind == "ended" }).count == 1,
                          let storedReason = existingEnd.endReason,
                          ConnectionSessionEndReason(rawValue: storedReason) != nil else {
                        throw ConnectionSessionAcquisitionRepositoryError.unavailable
                    }
                    if existingEnd.occurredAtMicroseconds == endedMicroseconds,
                       storedReason == reason.rawValue {
                        throw ConnectionSessionAcquisitionRepositoryError.duplicate
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
                guard endedMicroseconds >= started.occurredAtMicroseconds else {
                    throw ConnectionSessionAcquisitionRepositoryError.endBeforeStart
                }
                let record = ConnectionSessionAcquisitionRawBoundaryRecord(
                    sessionID: databaseKey(for: sessionID),
                    eventKind: "ended",
                    occurredAtMicroseconds: endedMicroseconds,
                    endReason: reason.rawValue
                )
                try record.insert(database)
                guard let readback = try ConnectionSessionAcquisitionRawBoundaryRecord.fetchOne(
                    database,
                    key: ["sessionID": databaseKey(for: sessionID), "eventKind": "ended"]
                ), readback.occurredAtMicroseconds == endedMicroseconds,
                      readback.endReason == reason.rawValue else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得終了境界保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// sessionのimmutable取得manifestを読み取ります。
    ///
    /// 責務: 正規化4表の完全なsealed aggregateをDomain manifestへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッションID。
    /// - Returns: 保存済み取得manifest。
    /// - Throws: 未登録は `.notFound`、不完全または読取失敗は `.unavailable`。
    func manifest(for sessionID: ConnectionSessionID) throws -> ConnectionSessionAcquisitionManifest {
        do {
            return try databaseQueue.read { database in
                guard let canonical = try readCanonicalStart(sessionID: sessionID, database: database) else {
                    throw ConnectionSessionAcquisitionRepositoryError.notFound
                }
                return canonical.manifest
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得manifest読取失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// sessionのRaw取得境界を開始、終了順で読み取ります。
    ///
    /// 責務: 保存済みmicrosecond境界行を変更せずDomain event列へ復元します。
    /// - Parameter sessionID: 読取対象の接続セッションID。
    /// - Returns: 開始から終了の順に並ぶ境界event。
    /// - Throws: 保存値破損または読取失敗は `.unavailable`。
    func boundaryEvidence(for sessionID: ConnectionSessionID) throws -> [AcquisitionRawBoundaryEvidence] {
        do {
            return try databaseQueue.read { database in
                let records = try boundaryRecords(sessionID: sessionID, database: database)
                try validateBoundarySequence(records)
                return try records.map { record in
                    let date = Date(timeIntervalSince1970: Double(record.occurredAtMicroseconds) / 1_000_000)
                    switch record.eventKind {
                    case "started" where record.endReason == nil:
                        return .started(at: date)
                    case "ended":
                        guard let rawReason = record.endReason,
                              let reason = ConnectionSessionEndReason(rawValue: rawReason) else {
                            throw ConnectionSessionAcquisitionRepositoryError.unavailable
                        }
                        return .ended(at: date, reason: reason)
                    default:
                        throw ConnectionSessionAcquisitionRepositoryError.unavailable
                    }
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得境界読取失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 未確定batchとpolicy選択済みrequest列を原子的に保存します。
    ///
    /// 責務: 物理要求前のopen batch aggregateをcanonical readback付きで1回だけ作成します。
    /// - Parameters:
    ///   - evidence: terminal結果を持たないbatch開始証拠。
    ///   - sessionID: batchを所有するsession。
    /// - Throws: 重複、競合、親manifest欠落、または保存失敗。
    func beginBatch(
        _ evidence: AcquisitionBatchEvidence,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            guard evidence.completionState == nil,
                  evidence.isSelectionEvaluationComplete,
                  evidence.requests.allSatisfy({ $0.dispatchState == .selectedOnly }) else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
            let key = databaseKey(for: sessionID)
            try measuredWrite(
                operation: .batchOpenPersistence,
                context: AcquisitionPerformanceContext(
                    generation: evidence.generation,
                    batchOrdinal: evidence.identity.ordinal,
                    policyTick: evidence.policyTick
                )
            ) { database in
                if let stored = try batchEvidence(
                    sessionID: sessionID,
                    batchOrdinal: evidence.identity.ordinal,
                    database: database
                ) {
                    guard stored == evidence else {
                        throw ConnectionSessionAcquisitionRepositoryError.conflict
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.duplicate
                }
                guard try String.fetchOne(
                    database,
                    sql: "SELECT sessionID FROM connection_session_acquisition_manifests WHERE sessionID = ? AND isSealed = 1",
                    arguments: [key]
                ) != nil else {
                    throw ConnectionSessionAcquisitionRepositoryError.startEvidenceMissing
                }
                let generation = try exactInt64(evidence.generation)
                let policyTick = try exactInt64(evidence.policyTick)
                try ConnectionSessionAcquisitionBatchRecord(
                    sessionID: key,
                    batchOrdinal: evidence.identity.ordinal,
                    generation: generation,
                    policyTick: policyTick,
                    selectionEvaluationComplete: evidence.isSelectionEvaluationComplete,
                    startedAtMicroseconds: try canonicalMicroseconds(for: evidence.startedAt),
                    completionState: nil,
                    completedAtMicroseconds: nil,
                    failureCode: nil,
                    isSealed: false
                ).insert(database)
                for request in evidence.requests {
                    try requestRecord(
                        request,
                        sessionID: key,
                        batchOrdinal: evidence.identity.ordinal
                    ).insert(database)
                }
                guard try batchEvidence(
                    sessionID: sessionID,
                    batchOrdinal: evidence.identity.ordinal,
                    database: database
                ) == evidence else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得batch開始保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// selected-only requestをdispatch開始へ単調遷移させます。
    ///
    /// 責務: 1件の要求が物理送信処理へ進む直前のdurable境界を冪等に保存します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: 親session。
    /// - Throws: request欠落、terminal済み競合、または保存失敗。
    func markRequestDispatchBegun(
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            try measuredWrite(
                operation: .requestDispatchPersistence,
                context: AcquisitionPerformanceContext(
                    batchOrdinal: batchIdentity.ordinal,
                    requestOrdinal: requestOrdinal
                )
            ) { database in
                let key = databaseKey(for: sessionID)
                guard let record = try ConnectionSessionAcquisitionPIDRequestRecord.fetchOne(
                    database,
                    key: ["sessionID": key, "batchOrdinal": batchIdentity.ordinal, "requestOrdinal": requestOrdinal]
                ) else {
                    throw ConnectionSessionAcquisitionRepositoryError.notFound
                }
                switch record.dispatchState {
                case PIDRequestDispatchState.dispatchBegun.rawValue:
                    throw ConnectionSessionAcquisitionRepositoryError.duplicate
                case PIDRequestDispatchState.selectedOnly.rawValue:
                    try database.execute(
                        sql: """
                            UPDATE connection_session_acquisition_pid_requests
                            SET dispatchState = 'dispatchBegun'
                            WHERE sessionID = ? AND batchOrdinal = ? AND requestOrdinal = ?
                            """,
                        arguments: [key, batchIdentity.ordinal, requestOrdinal]
                    )
                    guard database.changesCount == 1 else {
                        throw ConnectionSessionAcquisitionRepositoryError.unavailable
                    }
                default:
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("PID要求dispatch開始保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 正応答Rawと対応するrequest terminal証拠を1 transactionで保存します。
    ///
    /// 責務: dispatch開始済み要求へRawを採番追記しresponded terminalを原子的に確定します。
    /// - Parameters:
    ///   - observation: 既存Raw表へ追加する未デコード正応答。
    ///   - valueOutcome: 取得時定義による値評価結果。
    ///   - elapsedNanoseconds: 要求開始から正応答観測までの単調経過時間。
    ///   - reasonCode: transcript原文を含まない承認済み分類理由code。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: batchとRawを所有するsession。
    /// - Returns: 採番済みRaw sequenceを参照するcanonical request evidence。
    /// - Throws: dispatch前、sealed、重複、競合、所有関係不一致、または保存失敗。
    func saveRespondedRequest(
        observation: OBDRawResponseObservation,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        do {
            guard valueOutcome == .notEvaluated || valueOutcome == .decodedValid
                    || valueOutcome == .decodeFailure || valueOutcome == .invalidValue,
                  reasonCode?.isEmpty != true else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
            return try measuredWrite(
                operation: .respondedPersistence,
                context: AcquisitionPerformanceContext(
                    batchOrdinal: batchIdentity.ordinal,
                    requestOrdinal: requestOrdinal
                )
            ) { database in
                let key = databaseKey(for: sessionID)
                let stored = try requestForTerminalTransition(
                    requestOrdinal: requestOrdinal,
                    batchIdentity: batchIdentity,
                    sessionID: sessionID,
                    database: database
                )
                guard try requestMatchesManifest(
                    observation.request,
                    manifestPIDOrdinal: stored.manifestPIDOrdinal,
                    sessionKey: key,
                    database: database
                ) else {
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
                if stored.dispatchState == .terminal {
                    try classifyRespondedRetry(
                        stored: stored,
                        observation: observation,
                        valueOutcome: valueOutcome,
                        elapsedNanoseconds: elapsedNanoseconds,
                        reasonCode: reasonCode,
                        sessionID: sessionID,
                        database: database
                    )
                }
                guard stored.dispatchState == .dispatchBegun else {
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
                let rawEntry = try GRDBConnectionSessionRawLogAppender().append(
                    observation,
                    to: sessionID,
                    in: database
                )
                let expected = try PIDRequestEvidence(
                    requestOrdinal: requestOrdinal,
                    manifestPIDOrdinal: stored.manifestPIDOrdinal,
                    dispatchState: .terminal,
                    transportOutcome: .responded,
                    valueOutcome: valueOutcome,
                    rawSequence: rawEntry.sequence,
                    elapsedNanoseconds: elapsedNanoseconds,
                    reasonCode: reasonCode
                )
                try updateTerminalRequest(expected, sessionKey: key, batchIdentity: batchIdentity, database: database)
                guard let canonical = try storedRequest(
                    requestOrdinal: requestOrdinal,
                    batchIdentity: batchIdentity,
                    sessionID: sessionID,
                    database: database
                ), canonical == expected,
                      try rawEntryForSequence(rawEntry.sequence, sessionID: sessionID, database: database) == rawEntry else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
                return canonical
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("responded PID要求原子保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// Rawを持たないrequest terminal証拠を保存します。
    ///
    /// 責務: dispatch開始済み要求を確認済み非responded結果へcanonical readback付きで確定します。
    /// - Parameters:
    ///   - outcome: Rawを生成しない確認済みtransport結果。
    ///   - elapsedNanoseconds: 要求開始からterminal観測までの単調経過時間。回復時に不明なら `nil`。
    ///   - reasonCode: transcript原文を含まない承認済み分類理由code。
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: batchを所有するsession。
    /// - Returns: Raw参照を持たないcanonical request evidence。
    /// - Throws: responded指定、dispatch前、sealed、重複、競合、または保存失敗。
    func saveNonRespondedRequest(
        outcome: PIDRequestTransportOutcome,
        elapsedNanoseconds: UInt64?,
        reasonCode: String?,
        requestOrdinal: Int,
        in batchIdentity: AcquisitionBatchIdentity,
        for sessionID: ConnectionSessionID
    ) throws -> PIDRequestEvidence {
        do {
            guard outcome != .responded, reasonCode?.isEmpty != true else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
            return try measuredWrite(
                operation: .nonRespondedPersistence,
                context: AcquisitionPerformanceContext(
                    batchOrdinal: batchIdentity.ordinal,
                    requestOrdinal: requestOrdinal
                )
            ) { database in
                let key = databaseKey(for: sessionID)
                let stored = try requestForTerminalTransition(
                    requestOrdinal: requestOrdinal,
                    batchIdentity: batchIdentity,
                    sessionID: sessionID,
                    database: database
                )
                let expected = try PIDRequestEvidence(
                    requestOrdinal: requestOrdinal,
                    manifestPIDOrdinal: stored.manifestPIDOrdinal,
                    dispatchState: .terminal,
                    transportOutcome: outcome,
                    valueOutcome: .notEvaluated,
                    rawSequence: nil,
                    elapsedNanoseconds: elapsedNanoseconds,
                    reasonCode: reasonCode
                )
                if stored.dispatchState == .terminal {
                    guard stored == expected else {
                        throw ConnectionSessionAcquisitionRepositoryError.conflict
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.duplicate
                }
                guard stored.dispatchState == .dispatchBegun else {
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
                try updateTerminalRequest(expected, sessionKey: key, batchIdentity: batchIdentity, database: database)
                guard let canonical = try storedRequest(
                    requestOrdinal: requestOrdinal,
                    batchIdentity: batchIdentity,
                    sessionID: sessionID,
                    database: database
                ), canonical == expected else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
                return canonical
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("非responded PID要求保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// terminal request列とbatch終端を1 transactionで確定します。
    ///
    /// 責務: 既存Raw FKを検証しながらpartialを含むrequest結果とbatch sealを原子的に追記します。
    /// - Parameters:
    ///   - evidence: terminal状態を持つbatch証拠。
    ///   - sessionID: 親session。
    /// - Throws: 開始欠落、Raw参照欠落、重複、競合、または保存失敗。
    func finishBatch(
        _ evidence: AcquisitionBatchEvidence,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            guard evidence.completionState != nil,
                  let completedAt = evidence.completedAt else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
            let key = databaseKey(for: sessionID)
            try measuredWrite(
                operation: .batchSealPersistence,
                context: AcquisitionPerformanceContext(
                    generation: evidence.generation,
                    batchOrdinal: evidence.identity.ordinal,
                    policyTick: evidence.policyTick
                )
            ) { database in
                guard let stored = try batchEvidence(
                    sessionID: sessionID,
                    batchOrdinal: evidence.identity.ordinal,
                    database: database
                ) else {
                    throw ConnectionSessionAcquisitionRepositoryError.startEvidenceMissing
                }
                if stored.completionState != nil {
                    guard stored == evidence else {
                        throw ConnectionSessionAcquisitionRepositoryError.conflict
                    }
                    throw ConnectionSessionAcquisitionRepositoryError.duplicate
                }
                guard stored.identity == evidence.identity,
                      stored.generation == evidence.generation,
                      stored.policyTick == evidence.policyTick,
                      stored.isSelectionEvaluationComplete == evidence.isSelectionEvaluationComplete,
                      stored.startedAt == evidence.startedAt,
                      stored.requests.count == evidence.requests.count else {
                    throw ConnectionSessionAcquisitionRepositoryError.conflict
                }
                for request in evidence.requests where request.dispatchState == .terminal {
                    guard let current = try storedRequest(
                        requestOrdinal: request.requestOrdinal,
                        batchIdentity: evidence.identity,
                        sessionID: sessionID,
                        database: database
                    ) else {
                        throw ConnectionSessionAcquisitionRepositoryError.conflict
                    }
                    if current.dispatchState == .terminal {
                        guard current == request else {
                            throw ConnectionSessionAcquisitionRepositoryError.conflict
                        }
                    } else {
                        guard current.dispatchState == .dispatchBegun else {
                            throw ConnectionSessionAcquisitionRepositoryError.conflict
                        }
                        try updateTerminalRequest(
                            request,
                            sessionKey: key,
                            batchIdentity: evidence.identity,
                            database: database
                        )
                    }
                }
                try database.execute(
                    sql: """
                        UPDATE connection_session_acquisition_batches
                        SET completionState = ?, completedAtMicroseconds = ?, failureCode = ?, isSealed = 1
                        WHERE sessionID = ? AND batchOrdinal = ? AND isSealed = 0
                        """,
                    arguments: [
                        evidence.completionState?.rawValue,
                        try canonicalMicroseconds(for: completedAt),
                        evidence.failure?.rawValue,
                        key,
                        evidence.identity.ordinal
                    ]
                )
                guard database.changesCount == 1,
                      try batchEvidence(
                        sessionID: sessionID,
                        batchOrdinal: evidence.identity.ordinal,
                        database: database
                      ) == evidence else {
                    throw ConnectionSessionAcquisitionRepositoryError.unavailable
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得batch終端保存失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// sessionの全batch evidenceをordinal順で復元します。
    ///
    /// 責務: 正規化batch/request行をpartial状態を保持したDomain証拠列へ変換します。
    /// - Parameter sessionID: 読取対象session。
    /// - Returns: batch ordinal昇順の証拠列。
    /// - Throws: 保存値破損または読取失敗。
    func batches(for sessionID: ConnectionSessionID) throws -> [AcquisitionBatchEvidence] {
        do {
            return try databaseQueue.read { database in
                let records = try ConnectionSessionAcquisitionBatchRecord
                    .filter(Column("sessionID") == databaseKey(for: sessionID))
                    .order(Column("batchOrdinal"))
                    .fetchAll(database)
                return try records.map { record in
                    guard let evidence = try batchEvidence(
                        sessionID: sessionID,
                        batchOrdinal: record.batchOrdinal,
                        database: database
                    ) else {
                        throw ConnectionSessionAcquisitionRepositoryError.unavailable
                    }
                    return evidence
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("取得batch読取失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 現在session、open batch、取得終了境界を1 transactionで確定します。
    ///
    /// 責務: 1件の接続sessionを未確定batchの失敗sealを含む原子的な終了状態へ変換します。
    /// - Parameters:
    ///   - session: 終了直前の現在session。
    ///   - endedAt: sessionと取得境界へ共通で使用する終了日時。
    ///   - reason: 接続と取得が停止した直接原因。
    /// - Returns: transaction内でcanonical readbackした終了済みsession。
    /// - Throws: session不在、競合、取得境界不正、またはSQLite失敗。
    func finishSessionAcquisition(
        _ session: ConnectionSession,
        endedAt: Date,
        reason: ConnectionSessionEndReason
    ) throws -> ConnectionSession {
        do {
            return try measuredWrite(operation: .sessionTerminationPersistence) { database in
                try sealOpenBatchesAfterAcquisitionFailure(
                    sessionID: session.id,
                    completedAt: endedAt,
                    database: database
                )
                try appendEndIfAcquisitionStarted(
                    sessionID: session.id,
                    endedAt: endedAt,
                    reason: reason,
                    database: database
                )
                return try finishSessionRecord(
                    session,
                    endedAt: endedAt,
                    reason: reason,
                    database: database
                )
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("接続session取得終了失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// アカウントに残る未終了sessionとopen取得証拠を1 transactionで回復します。
    ///
    /// 責務: process終了後に残った全sessionを決定的な異常終了状態へ変換します。
    /// - Parameters:
    ///   - accountIdentifier: 回復対象sessionの所有アカウント。
    ///   - recoveredAt: 回復結果へ固定する終了日時。
    /// - Returns: 今回回復した終了済みsession。
    /// - Throws: 保存値不正またはSQLite回復失敗。
    func recoverInterruptedSessionAcquisitions(
        for accountIdentifier: String,
        recoveredAt: Date
    ) throws -> [ConnectionSession] {
        do {
            return try measuredWrite(operation: .terminationRecoveryPersistence) { database in
                let records = try ConnectionSessionRecord
                    .filter(Column("accountIdentifier") == accountIdentifier && Column("endedAt") == nil)
                    .order(Column("startedAt"))
                    .fetchAll(database)
                return try records.map { record in
                    guard let session = record.makeDomainSession() else {
                        throw ConnectionSessionAcquisitionRepositoryError.unavailable
                    }
                    try recoverOpenBatchesAfterProcessTermination(
                        sessionID: session.id,
                        completedAt: recoveredAt,
                        database: database
                    )
                    try appendEndIfAcquisitionStarted(
                        sessionID: session.id,
                        endedAt: recoveredAt,
                        reason: .unexpectedTermination,
                        database: database
                    )
                    return try finishSessionRecord(
                        session,
                        endedAt: recoveredAt,
                        reason: .unexpectedTermination,
                        database: database
                    )
                }
            }
        } catch let error as ConnectionSessionAcquisitionRepositoryError {
            throw error
        } catch {
            logger.error("中断session取得回復失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// 1回のGRDB writeをQueue通過点付きperformance区間として実行します。
    ///
    /// 責務: 匿名取得位置をSQLite Queue待機とtransactionを含む単一の計測済みwriteへ変換します。
    /// - Parameters:
    ///   - operation: writeが所有する取得性能操作。
    ///   - context: 個人・端末・車両識別子を含まない取得位置。
    ///   - updates: Queue内で実行する既存の原子更新。
    /// - Returns: 既存write closureが返した値。
    /// - Throws: 既存write closureまたはGRDBが返した同じエラー。
    private func measuredWrite<Value>(
        operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext = AcquisitionPerformanceContext(),
        _ updates: (Database) throws -> Value
    ) throws -> Value {
        let interval = performanceEvents.begin(operation, context: context)
        do {
            let value = try databaseQueue.write { database in
                performanceEvents.queueDidEnter(interval)
                return try updates(database)
            }
            performanceEvents.end(interval, outcome: .succeeded)
            return value
        } catch {
            performanceEvents.end(interval, outcome: .failed)
            throw error
        }
    }

    /// graceful終了時に残ったopen batchをpersistence failureとしてsealします。
    ///
    /// 責務: session終了直前の未確定batchを新しい物理結果を推測せず失敗状態へ閉じます。
    /// - Parameters:
    ///   - sessionID: batchを所有するsession。
    ///   - completedAt: batch失敗を確定する日時。
    ///   - database: 親transactionのSQLite境界。
    /// - Throws: batch復元または更新に失敗した場合のrepository error。
    private func sealOpenBatchesAfterAcquisitionFailure(
        sessionID: ConnectionSessionID,
        completedAt: Date,
        database: Database
    ) throws {
        let records = try openBatchRecords(sessionID: sessionID, database: database)
        for record in records {
            guard let open = try batchEvidence(
                sessionID: sessionID,
                batchOrdinal: record.batchOrdinal,
                database: database
            ) else { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
            let terminal = try AcquisitionBatchEvidence(
                identity: open.identity,
                generation: open.generation,
                policyTick: open.policyTick,
                isSelectionEvaluationComplete: open.isSelectionEvaluationComplete,
                startedAt: open.startedAt,
                completionState: .failed,
                completedAt: max(completedAt, open.startedAt),
                failure: .persistenceFailure,
                requests: open.requests
            )
            try sealBatch(terminal, sessionID: sessionID, database: database)
        }
    }

    /// process終了後のdispatch済み要求をunknownへ変換してopen batchをsealします。
    ///
    /// 責務: 1件のsessionに残る全open batchを再送なしのtermination証拠へ変換します。
    /// - Parameters:
    ///   - sessionID: batchを所有するsession。
    ///   - completedAt: 回復を確定する日時。
    ///   - database: 親transactionのSQLite境界。
    /// - Throws: request更新またはbatch sealに失敗した場合のrepository error。
    private func recoverOpenBatchesAfterProcessTermination(
        sessionID: ConnectionSessionID,
        completedAt: Date,
        database: Database
    ) throws {
        let records = try openBatchRecords(sessionID: sessionID, database: database)
        for record in records {
            guard let open = try batchEvidence(
                sessionID: sessionID,
                batchOrdinal: record.batchOrdinal,
                database: database
            ) else { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
            var requests = open.requests
            for request in open.requests where request.dispatchState == .dispatchBegun {
                let terminal = try PIDRequestEvidence(
                    requestOrdinal: request.requestOrdinal,
                    manifestPIDOrdinal: request.manifestPIDOrdinal,
                    dispatchState: .terminal,
                    transportOutcome: .unknownAfterTermination,
                    valueOutcome: .notEvaluated,
                    rawSequence: nil,
                    elapsedNanoseconds: nil,
                    reasonCode: "process_terminated_after_dispatch"
                )
                try updateTerminalRequest(
                    terminal,
                    sessionKey: databaseKey(for: sessionID),
                    batchIdentity: open.identity,
                    database: database
                )
                requests[request.requestOrdinal] = terminal
            }
            let terminal = try AcquisitionBatchEvidence(
                identity: open.identity,
                generation: open.generation,
                policyTick: open.policyTick,
                isSelectionEvaluationComplete: open.isSelectionEvaluationComplete,
                startedAt: open.startedAt,
                completionState: .terminatedUnknown,
                completedAt: max(completedAt, open.startedAt),
                failure: .processTerminated,
                requests: requests
            )
            try sealBatch(terminal, sessionID: sessionID, database: database)
        }
    }

    /// sessionの未seal batch行をordinal順で返します。
    ///
    /// 責務: 1件のsessionから回復対象のopen batchだけを安定順で選択します。
    /// - Parameters:
    ///   - sessionID: batchを所有するsession。
    ///   - database: 現在のSQLite境界。
    /// - Returns: batch ordinal昇順の未seal行。
    /// - Throws: SQLite読取失敗。
    private func openBatchRecords(
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> [ConnectionSessionAcquisitionBatchRecord] {
        try ConnectionSessionAcquisitionBatchRecord
            .filter(Column("sessionID") == databaseKey(for: sessionID) && Column("isSealed") == false)
            .order(Column("batchOrdinal"))
            .fetchAll(database)
    }

    /// 親transaction内で1件のterminal batchをcanonical readback付きでsealします。
    ///
    /// 責務: 回復済みbatch終端を既存request列との整合確認後に確定します。
    /// - Parameters:
    ///   - evidence: 保存するterminal batch証拠。
    ///   - sessionID: batchを所有するsession。
    ///   - database: 親transactionのSQLite境界。
    /// - Throws: 更新競合またはcanonical readback不一致。
    private func sealBatch(
        _ evidence: AcquisitionBatchEvidence,
        sessionID: ConnectionSessionID,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                UPDATE connection_session_acquisition_batches
                SET completionState = ?, completedAtMicroseconds = ?, failureCode = ?, isSealed = 1
                WHERE sessionID = ? AND batchOrdinal = ? AND isSealed = 0
                """,
            arguments: [
                evidence.completionState?.rawValue,
                try evidence.completedAt.map(canonicalMicroseconds),
                evidence.failure?.rawValue,
                databaseKey(for: sessionID),
                evidence.identity.ordinal
            ]
        )
        guard database.changesCount == 1,
              try batchEvidence(
                sessionID: sessionID,
                batchOrdinal: evidence.identity.ordinal,
                database: database
              ) == evidence else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// manifest開始済みsessionへ終了境界を親transaction内で追記します。
    ///
    /// 責務: 取得開始の有無を保ったまま存在する取得だけへ終了境界を追加します。
    /// - Parameters:
    ///   - sessionID: 終了対象session。
    ///   - endedAt: 終了境界日時。
    ///   - reason: 取得停止理由。
    ///   - database: 親transactionのSQLite境界。
    /// - Throws: 境界競合、時系列違反、またはSQLite失敗。
    private func appendEndIfAcquisitionStarted(
        sessionID: ConnectionSessionID,
        endedAt: Date,
        reason: ConnectionSessionEndReason,
        database: Database
    ) throws {
        let boundaries = try boundaryRecords(sessionID: sessionID, database: database)
        guard let started = boundaries.first(where: { $0.eventKind == "started" }) else {
            guard boundaries.isEmpty else { throw ConnectionSessionAcquisitionRepositoryError.unavailable }
            return
        }
        let endedMicroseconds = try canonicalMicroseconds(for: endedAt)
        if let ended = boundaries.first(where: { $0.eventKind == "ended" }) {
            guard ended.occurredAtMicroseconds == endedMicroseconds,
                  ended.endReason == reason.rawValue else {
                throw ConnectionSessionAcquisitionRepositoryError.conflict
            }
            return
        }
        guard endedMicroseconds >= started.occurredAtMicroseconds else {
            throw ConnectionSessionAcquisitionRepositoryError.endBeforeStart
        }
        try ConnectionSessionAcquisitionRawBoundaryRecord(
            sessionID: databaseKey(for: sessionID),
            eventKind: "ended",
            occurredAtMicroseconds: endedMicroseconds,
            endReason: reason.rawValue
        ).insert(database)
    }

    /// 現在sessionを親transaction内で終了しcanonical値を返します。
    ///
    /// 責務: 1件の未終了sessionへ終了日時と理由を保存して同じ行を復元します。
    /// - Parameters:
    ///   - session: 終了直前のApplication保持値。
    ///   - endedAt: 保存する終了日時。
    ///   - reason: 保存する終了理由。
    ///   - database: 親transactionのSQLite境界。
    /// - Returns: 保存済み終了session。
    /// - Throws: session不在、既終了、またはreadback不正。
    private func finishSessionRecord(
        _ session: ConnectionSession,
        endedAt: Date,
        reason: ConnectionSessionEndReason,
        database: Database
    ) throws -> ConnectionSession {
        let key = databaseKey(for: session.id)
        guard let stored = try ConnectionSessionRecord.fetchOne(database, key: key),
              stored.endedAt == nil,
              let storedDomain = stored.makeDomainSession() else {
            throw ConnectionSessionAcquisitionRepositoryError.conflict
        }
        var ended = session
        ended.rawLogSummary = storedDomain.rawLogSummary
        ended.endedAt = endedAt
        ended.endReason = reason
        try ConnectionSessionRecord(session: ended).save(database)
        guard let readback = try ConnectionSessionRecord.fetchOne(database, key: key)?.makeDomainSession(),
              readback == ended else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return readback
    }

    /// UInt値をSQLiteの非負Int64へ変換します。
    ///
    /// 責務: 取得世代、tick、経過時間を表現範囲検証済みSQLite整数へ変換します。
    /// - Parameter value: 変換する非負値。
    /// - Returns: 同じ値を持つInt64。
    /// - Throws: Int64範囲外の場合は `.unavailable`。
    private func exactInt64(_ value: UInt) throws -> Int64 {
        guard let converted = Int64(exactly: value) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return converted
    }

    /// UInt64値をSQLiteの非負Int64へ変換します。
    ///
    /// 責務: 単調経過時間を表現範囲検証済みSQLite整数へ変換します。
    /// - Parameter value: 変換する非負値。
    /// - Returns: 同じ値を持つInt64。
    /// - Throws: Int64範囲外の場合は `.unavailable`。
    private func exactInt64(_ value: UInt64) throws -> Int64 {
        guard let converted = Int64(exactly: value) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return converted
    }

    /// Domain request evidenceをGRDB行へ変換します。
    ///
    /// 責務: 1件の要求証拠を親session/batch付き永続化表現へ変換します。
    /// - Parameters:
    ///   - request: 変換する要求証拠。
    ///   - sessionID: 親session DB key。
    ///   - batchOrdinal: 親batch番号。
    /// - Returns: 挿入可能なrequest record。
    /// - Throws: 経過時間がInt64範囲外の場合は `.unavailable`。
    private func requestRecord(
        _ request: PIDRequestEvidence,
        sessionID: String,
        batchOrdinal: Int64
    ) throws -> ConnectionSessionAcquisitionPIDRequestRecord {
        try ConnectionSessionAcquisitionPIDRequestRecord(
            sessionID: sessionID,
            batchOrdinal: batchOrdinal,
            requestOrdinal: request.requestOrdinal,
            manifestPIDOrdinal: request.manifestPIDOrdinal,
            dispatchState: request.dispatchState.rawValue,
            transportOutcome: request.transportOutcome?.rawValue,
            valueOutcome: request.valueOutcome.rawValue,
            rawSequence: request.rawSequence,
            elapsedNanoseconds: request.elapsedNanoseconds.map(exactInt64),
            reasonCode: request.reasonCode,
            isSealed: request.dispatchState == .terminal
        )
    }

    /// terminal遷移対象の親manifest、open batch、requestを読み取ります。
    ///
    /// 責務: 1件のrequest terminal書込前提を保存済み所有関係とseal状態から検証します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: 親session。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 保存済みcanonical request evidence。
    /// - Throws: manifest、batch、request欠落またはsealed batchではrepository error。
    private func requestForTerminalTransition(
        requestOrdinal: Int,
        batchIdentity: AcquisitionBatchIdentity,
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> PIDRequestEvidence {
        let key = databaseKey(for: sessionID)
        guard try String.fetchOne(
            database,
            sql: "SELECT sessionID FROM connection_session_acquisition_manifests WHERE sessionID = ? AND isSealed = 1",
            arguments: [key]
        ) != nil,
              let batch = try ConnectionSessionAcquisitionBatchRecord.fetchOne(
                database,
                key: ["sessionID": key, "batchOrdinal": batchIdentity.ordinal]
              ) else {
            throw ConnectionSessionAcquisitionRepositoryError.conflict
        }
        guard let request = try storedRequest(
            requestOrdinal: requestOrdinal,
            batchIdentity: batchIdentity,
            sessionID: sessionID,
            database: database
        ) else {
            throw ConnectionSessionAcquisitionRepositoryError.notFound
        }
        guard !batch.isSealed || request.dispatchState == .terminal else {
            throw ConnectionSessionAcquisitionRepositoryError.conflict
        }
        return request
    }

    /// manifest ordered PID位置とRaw observation要求の一致を確認します。
    ///
    /// 責務: request evidenceが参照するmanifest PIDをRawのService/PID所有関係と照合します。
    /// - Parameters:
    ///   - request: Raw observationのService/PID要求。
    ///   - manifestPIDOrdinal: request evidenceが参照するmanifest位置。
    ///   - sessionKey: 親sessionのDB key。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 保存済みordered PIDと完全一致する場合は `true`。
    /// - Throws: SQLite読込失敗。
    private func requestMatchesManifest(
        _ request: OBDPIDRequest,
        manifestPIDOrdinal: Int,
        sessionKey: String,
        database: Database
    ) throws -> Bool {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT service, pid FROM connection_session_acquisition_ordered_pids WHERE sessionID = ? AND ordinal = ?",
            arguments: [sessionKey, manifestPIDOrdinal]
        ) else { return false }
        let service: Int = row["service"]
        let pid: Int = row["pid"]
        return service == Int(request.service) && pid == Int(request.pid)
    }

    /// 既存responded terminalへのretryをduplicateまたはconflictへ分類します。
    ///
    /// 責務: 保存済みRawとrequest evidenceをretry入力の全semantic fieldへ照合します。
    /// - Parameters:
    ///   - stored: 保存済みterminal request evidence。
    ///   - observation: retryされたRaw observation。
    ///   - valueOutcome: retryされた値評価結果。
    ///   - elapsedNanoseconds: retryされたterminal経過時間。
    ///   - reasonCode: retryされた分類理由code。
    ///   - sessionID: Rawを所有するsession。
    ///   - database: 現在のSQLite境界。
    /// - Throws: 完全一致は `.duplicate`、差異または欠損は `.conflict`。
    private func classifyRespondedRetry(
        stored: PIDRequestEvidence,
        observation: OBDRawResponseObservation,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64,
        reasonCode: String?,
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> Never {
        guard stored.transportOutcome == .responded,
              stored.valueOutcome == valueOutcome,
              stored.elapsedNanoseconds == elapsedNanoseconds,
              stored.reasonCode == reasonCode,
              let sequence = stored.rawSequence,
              let raw = try rawEntryForSequence(sequence, sessionID: sessionID, database: database),
              raw.observedAt == observation.observedAt,
              raw.batchElapsedNanoseconds == observation.batchElapsedNanoseconds,
              raw.service == observation.request.service,
              raw.pid == observation.request.pid,
              raw.payload == observation.payload else {
            throw ConnectionSessionAcquisitionRepositoryError.conflict
        }
        throw ConnectionSessionAcquisitionRepositoryError.duplicate
    }

    /// request evidenceをterminal列へ単調更新します。
    ///
    /// 責務: 1件のcanonical terminal証拠を未seal request行へ反映します。
    /// - Parameters:
    ///   - evidence: 保存するterminal request evidence。
    ///   - sessionKey: 親sessionのDB key。
    ///   - batchIdentity: 親batch identity。
    ///   - database: 現在のSQLite境界。
    /// - Throws: 更新件数が1件でない場合は `.conflict`、SQLite失敗は上位へ送出。
    private func updateTerminalRequest(
        _ evidence: PIDRequestEvidence,
        sessionKey: String,
        batchIdentity: AcquisitionBatchIdentity,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                UPDATE connection_session_acquisition_pid_requests
                SET dispatchState = ?, transportOutcome = ?, valueOutcome = ?, rawSequence = ?,
                    elapsedNanoseconds = ?, reasonCode = ?, isSealed = 1
                WHERE sessionID = ? AND batchOrdinal = ? AND requestOrdinal = ? AND isSealed = 0
                """,
            arguments: [
                evidence.dispatchState.rawValue,
                evidence.transportOutcome?.rawValue,
                evidence.valueOutcome.rawValue,
                evidence.rawSequence,
                try evidence.elapsedNanoseconds.map(exactInt64),
                evidence.reasonCode,
                sessionKey,
                batchIdentity.ordinal,
                evidence.requestOrdinal
            ]
        )
        guard database.changesCount == 1 else {
            throw ConnectionSessionAcquisitionRepositoryError.conflict
        }
    }

    /// 保存済み1件のrequest evidenceを復元します。
    ///
    /// 責務: request主キーをDomain不変条件で検証したcanonical evidenceへ変換します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - batchIdentity: 親batch identity。
    ///   - sessionID: 親session。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 保存済みrequest、または不在時の `nil`。
    /// - Throws: 保存値が不正な場合は `.unavailable`。
    private func storedRequest(
        requestOrdinal: Int,
        batchIdentity: AcquisitionBatchIdentity,
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> PIDRequestEvidence? {
        guard let record = try ConnectionSessionAcquisitionPIDRequestRecord.fetchOne(
            database,
            key: [
                "sessionID": databaseKey(for: sessionID),
                "batchOrdinal": batchIdentity.ordinal,
                "requestOrdinal": requestOrdinal
            ]
        ) else { return nil }
        return try requestEvidence(from: record)
    }

    /// 保存済みRaw sequenceをDomain entryへ復元します。
    ///
    /// 責務: session内Raw主キーを検証済み未デコードentryへ変換します。
    /// - Parameters:
    ///   - sequence: session内Raw sequence。
    ///   - sessionID: Rawを所有するsession。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 保存済みRaw entry、または不在時の `nil`。
    /// - Throws: 保存値が不正な場合は `.unavailable`。
    private func rawEntryForSequence(
        _ sequence: Int64,
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> ConnectionSessionRawLogEntry? {
        guard let record = try ConnectionSessionRawLogRecord.fetchOne(
            database,
            key: ["sessionID": databaseKey(for: sessionID), "sequence": sequence]
        ) else { return nil }
        guard let entry = record.makeDomainEntry() else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return entry
    }

    /// GRDB request行をDomain evidenceへ復元します。
    ///
    /// 責務: 1件のrequest保存値をenumと整数範囲検証済みDomain値へ変換します。
    /// - Parameter record: 復元するrequest行。
    /// - Returns: canonical request evidence。
    /// - Throws: enum、整数、またはDomain不変条件が不正な場合は `.unavailable`。
    private func requestEvidence(
        from record: ConnectionSessionAcquisitionPIDRequestRecord
    ) throws -> PIDRequestEvidence {
        guard let dispatchState = PIDRequestDispatchState(rawValue: record.dispatchState),
              let valueOutcome = PIDRequestValueOutcome(rawValue: record.valueOutcome) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let elapsed: UInt64?
        if let storedElapsed = record.elapsedNanoseconds {
            guard let converted = UInt64(exactly: storedElapsed) else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            elapsed = converted
        } else {
            elapsed = nil
        }
        let transportOutcome = try record.transportOutcome.map { raw -> PIDRequestTransportOutcome in
            guard let value = PIDRequestTransportOutcome(rawValue: raw) else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            return value
        }
        return try PIDRequestEvidence(
            requestOrdinal: record.requestOrdinal,
            manifestPIDOrdinal: record.manifestPIDOrdinal,
            dispatchState: dispatchState,
            transportOutcome: transportOutcome,
            valueOutcome: valueOutcome,
            rawSequence: record.rawSequence,
            elapsedNanoseconds: elapsed,
            reasonCode: record.reasonCode
        )
    }

    /// 正規化行から1件のbatch evidenceを復元します。
    ///
    /// 責務: batch rowとrequest row列をDomain不変条件で検証したaggregateへ変換します。
    /// - Parameters:
    ///   - sessionID: 親session。
    ///   - batchOrdinal: 読み取るbatch番号。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 未登録なら `nil`、登録済みならpartialを保持するbatch evidence。
    /// - Throws: enum、整数、時系列、不変条件が不正な場合は `.unavailable`。
    private func batchEvidence(
        sessionID: ConnectionSessionID,
        batchOrdinal: Int64,
        database: Database
    ) throws -> AcquisitionBatchEvidence? {
        let key = databaseKey(for: sessionID)
        guard let batch = try ConnectionSessionAcquisitionBatchRecord.fetchOne(
            database,
            key: ["sessionID": key, "batchOrdinal": batchOrdinal]
        ) else { return nil }
        let requestRecords = try ConnectionSessionAcquisitionPIDRequestRecord
            .filter(Column("sessionID") == key && Column("batchOrdinal") == batchOrdinal)
            .order(Column("requestOrdinal"))
            .fetchAll(database)
        let requests = try requestRecords.map(requestEvidence)
        guard let generation = UInt(exactly: batch.generation),
              let policyTick = UInt(exactly: batch.policyTick) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let completionState = try batch.completionState.map { raw -> AcquisitionBatchCompletionState in
            guard let value = AcquisitionBatchCompletionState(rawValue: raw) else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            return value
        }
        let failure = try batch.failureCode.map { raw -> AcquisitionBatchFailure in
            guard let value = AcquisitionBatchFailure(rawValue: raw) else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            return value
        }
        return try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: batch.batchOrdinal),
            generation: generation,
            policyTick: policyTick,
            isSelectionEvaluationComplete: batch.selectionEvaluationComplete,
            startedAt: Date(timeIntervalSince1970: Double(batch.startedAtMicroseconds) / 1_000_000),
            completionState: completionState,
            completedAt: batch.completedAtMicroseconds.map {
                Date(timeIntervalSince1970: Double($0) / 1_000_000)
            },
            failure: failure,
            requests: requests
        )
    }

    /// 入力manifestと開始時刻をDB比較用のcanonical値へ変換します。
    ///
    /// 責務: PID snapshot順を除外し要求順とmicrosecond時刻を保持する比較値を生成します。
    /// - Parameters:
    ///   - manifest: canonical化する完全manifest。
    ///   - startedAt: canonical化する開始時刻。
    /// - Returns: DB readbackと比較できるcanonical開始aggregate。
    /// - Throws: semantic field欠落または時刻変換不能の場合は `.unavailable`。
    private func canonicalStart(
        manifest: ConnectionSessionAcquisitionManifest,
        startedAt: Date
    ) throws -> CanonicalAcquisitionStart {
        guard let orderedRequestedPIDs = manifest.orderedRequestedPIDs else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let sortedDefinitions = manifest.pidDefinitions.sorted(by: pidDefinitionPrecedes)
        let canonicalManifest = try ConnectionSessionAcquisitionManifest(
            manifestVersion: manifest.manifestVersion,
            applicationVersion: manifest.applicationVersion,
            schemaContractVersion: manifest.schemaContractVersion,
            pollingPolicyVersion: manifest.pollingPolicyVersion,
            orderedRequestedPIDs: orderedRequestedPIDs,
            pidDefinitions: sortedDefinitions,
            acquisitionPlatform: manifest.acquisitionPlatform,
            modelInputManifestVersion: manifest.modelInputManifestVersion
        )
        try validateComplete(manifest: canonicalManifest)
        return CanonicalAcquisitionStart(
            manifest: canonicalManifest,
            startedAtMicroseconds: try canonicalMicroseconds(for: startedAt)
        )
    }

    /// DateをUnix epoch基準の整数microsecondへ変換します。
    ///
    /// 責務: 有限かつInt64範囲内の時刻を最近傍microsecondへcanonical化します。
    /// - Parameter date: canonical化する日時。
    /// - Returns: Unix epochからの符号付きmicrosecond。
    /// - Throws: 非有限または表現範囲外の場合は `.unavailable`。
    private func canonicalMicroseconds(for date: Date) throws -> Int64 {
        let scaled = date.timeIntervalSince1970 * 1_000_000
        guard scaled.isFinite,
              scaled >= -9_223_372_036_854_775_808.0,
              scaled < 9_223_372_036_854_775_808.0 else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return Int64(scaled.rounded(.toNearestOrAwayFromZero))
    }

    /// 新規開始aggregateを未確定から確定まで同じSQLite transactionへ挿入します。
    ///
    /// 責務: manifest、PID定義、要求順、開始境界を順に保存して最後にsealします。
    /// - Parameters:
    ///   - start: 保存するcanonical開始aggregate。
    ///   - sessionID: 親接続セッションのDB key。
    ///   - database: 現在のSQLite書込境界。
    /// - Throws: 挿入またはsealに失敗した場合のGRDBエラー。
    private func insertStart(
        _ start: CanonicalAcquisitionStart,
        sessionID: String,
        database: Database
    ) throws {
        let manifest = start.manifest
        guard let manifestVersion = manifest.manifestVersion,
              let applicationVersion = manifest.applicationVersion,
              let schemaContractVersion = manifest.schemaContractVersion,
              let pollingPolicyVersion = manifest.pollingPolicyVersion,
              let orderedRequestedPIDs = manifest.orderedRequestedPIDs,
              let acquisitionPlatform = manifest.acquisitionPlatform,
              let modelInputManifestVersion = manifest.modelInputManifestVersion else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        try ConnectionSessionAcquisitionManifestRecord(
            sessionID: sessionID,
            manifestVersion: manifestVersion,
            applicationMarketingVersion: applicationVersion.marketingVersion,
            applicationBuildVersion: applicationVersion.buildVersion,
            schemaContractVersion: schemaContractVersion,
            pollingPolicyVersion: pollingPolicyVersion,
            acquisitionPlatform: acquisitionPlatform.rawValue,
            modelInputManifestVersion: modelInputManifestVersion,
            isSealed: false
        ).insert(database)
        for definition in manifest.pidDefinitions {
            try pidDefinitionRecord(definition, sessionID: sessionID).insert(database)
        }
        for (ordinal, request) in orderedRequestedPIDs.requests.enumerated() {
            try ConnectionSessionAcquisitionOrderedPIDRecord(
                sessionID: sessionID,
                ordinal: ordinal,
                service: Int(request.service),
                pid: Int(request.pid)
            ).insert(database)
        }
        try ConnectionSessionAcquisitionRawBoundaryRecord(
            sessionID: sessionID,
            eventKind: "started",
            occurredAtMicroseconds: start.startedAtMicroseconds,
            endReason: nil
        ).insert(database)
        try database.execute(
            sql: "UPDATE connection_session_acquisition_manifests SET isSealed = 1 WHERE sessionID = ? AND isSealed = 0",
            arguments: [sessionID]
        )
        guard database.changesCount == 1 else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// Domain PID snapshotを完全な永続化行へ変換します。
    ///
    /// 責務: 1件の完全PID snapshotを範囲kindを明示したDB列へ変換します。
    /// - Parameters:
    ///   - definition: 変換するPID snapshot。
    ///   - sessionID: 親接続セッションのDB key。
    /// - Returns: 挿入可能なPID定義record。
    /// - Throws: semantic fieldが欠落する場合は `.unavailable`。
    private func pidDefinitionRecord(
        _ definition: AcquisitionPIDDefinitionSnapshot,
        sessionID: String
    ) throws -> ConnectionSessionAcquisitionPIDDefinitionRecord {
        guard let capabilitySupport = definition.capabilitySupport,
              let isCollectionEnabled = definition.isCollectionEnabled,
              let definitionRevision = definition.definitionRevision,
              let requiredByteCount = definition.requiredByteCount,
              let identity = definition.definitionIdentity,
              let unit = definition.unit,
              !unit.isEmpty,
              let validityRange = definition.validityRange else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let rangeKind = validityRange.minimum == nil ? "notDeclared" : "inclusive"
        return ConnectionSessionAcquisitionPIDDefinitionRecord(
            sessionID: sessionID,
            service: Int(definition.request.service),
            pid: Int(definition.request.pid),
            capabilitySupport: capabilitySupport.rawValue,
            isCollectionEnabled: isCollectionEnabled,
            definitionRevision: definitionRevision,
            requiredByteCount: requiredByteCount,
            formulaCanonicalizationVersion: identity.canonicalizationVersion,
            formulaExpression: identity.expression,
            unit: unit,
            validityRangeKind: rangeKind,
            minimumValue: validityRange.minimum,
            maximumValue: validityRange.maximum
        )
    }

    /// DBの4表から完全なcanonical開始aggregateを読み取ります。
    ///
    /// 責務: 1件のsessionに属するsealed manifest、PID集合、要求順、開始境界を破損検知付きで復元します。
    /// - Parameters:
    ///   - sessionID: 読取対象の接続セッションID。
    ///   - database: 現在のSQLite読取境界。
    /// - Returns: 全行が未保存なら `nil`、完全保存ならcanonical aggregate。
    /// - Throws: 部分状態、decode不能、ordinal不連続では `.unavailable`。
    private func readCanonicalStart(
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> CanonicalAcquisitionStart? {
        let key = databaseKey(for: sessionID)
        let manifestRecord = try ConnectionSessionAcquisitionManifestRecord.fetchOne(database, key: key)
        let definitions = try ConnectionSessionAcquisitionPIDDefinitionRecord
            .filter(Column("sessionID") == key)
            .order(Column("service"), Column("pid"))
            .fetchAll(database)
        let ordered = try ConnectionSessionAcquisitionOrderedPIDRecord
            .filter(Column("sessionID") == key)
            .order(Column("ordinal"))
            .fetchAll(database)
        let boundaries = try boundaryRecords(sessionID: sessionID, database: database)
        try validateBoundarySequence(boundaries)
        guard let manifestRecord else {
            guard definitions.isEmpty, ordered.isEmpty, boundaries.isEmpty else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            return nil
        }
        guard manifestRecord.isSealed,
              let started = boundaries.first(where: { $0.eventKind == "started" }),
              boundaries.filter({ $0.eventKind == "started" }).count == 1,
              started.endReason == nil,
              ordered.enumerated().allSatisfy({ $0.offset == $0.element.ordinal }) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let domainDefinitions = try definitions.map(makeDomainPIDDefinition)
        let requests = try ordered.map { record -> OBDPIDRequest in
            guard let service = UInt8(exactly: record.service),
                  let pid = UInt8(exactly: record.pid) else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            return OBDPIDRequest(service: service, pid: pid)
        }
        let applicationVersion = try AcquisitionApplicationVersion(
            marketingVersion: manifestRecord.applicationMarketingVersion,
            buildVersion: manifestRecord.applicationBuildVersion
        )
        guard let platform = ConnectionSessionAcquisitionPlatform(rawValue: manifestRecord.acquisitionPlatform) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let manifest = try ConnectionSessionAcquisitionManifest(
            manifestVersion: manifestRecord.manifestVersion,
            applicationVersion: applicationVersion,
            schemaContractVersion: manifestRecord.schemaContractVersion,
            pollingPolicyVersion: manifestRecord.pollingPolicyVersion,
            orderedRequestedPIDs: try OrderedAcquisitionPIDSet(requests: requests),
            pidDefinitions: domainDefinitions,
            acquisitionPlatform: platform,
            modelInputManifestVersion: manifestRecord.modelInputManifestVersion
        )
        try validateComplete(manifest: manifest)
        return CanonicalAcquisitionStart(manifest: manifest, startedAtMicroseconds: started.occurredAtMicroseconds)
    }

    /// 永続化PID行をDomain snapshotへ復元します。
    ///
    /// 責務: 1件の検証済みPID定義recordを完全なDomain snapshotへ変換します。
    /// - Parameter record: 復元する永続化record。
    /// - Returns: 完全な取得時PID snapshot。
    /// - Throws: enum、数値、範囲の保存値が不正な場合は `.unavailable`。
    private func makeDomainPIDDefinition(
        _ record: ConnectionSessionAcquisitionPIDDefinitionRecord
    ) throws -> AcquisitionPIDDefinitionSnapshot {
        guard let service = UInt8(exactly: record.service),
              let pid = UInt8(exactly: record.pid),
              let capability = AcquisitionPIDCapabilitySupport(rawValue: record.capabilitySupport) else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        let validityRange: AcquisitionPIDValidityRange
        switch record.validityRangeKind {
        case "notDeclared" where record.minimumValue == nil && record.maximumValue == nil:
            validityRange = .notDeclared
        case "inclusive":
            guard let minimum = record.minimumValue, let maximum = record.maximumValue else {
                throw ConnectionSessionAcquisitionRepositoryError.unavailable
            }
            validityRange = try .inclusive(minimum: minimum, maximum: maximum)
        default:
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        return try AcquisitionPIDDefinitionSnapshot(
            request: OBDPIDRequest(service: service, pid: pid),
            capabilitySupport: capability,
            isCollectionEnabled: record.isCollectionEnabled,
            definitionRevision: record.definitionRevision,
            requiredByteCount: record.requiredByteCount,
            definitionIdentity: try AcquisitionPIDDefinitionIdentity(
                canonicalizationVersion: record.formulaCanonicalizationVersion,
                expression: record.formulaExpression
            ),
            unit: record.unit,
            validityRange: validityRange
        )
    }

    /// manifestが新規保存に必要な全semantic fieldを持つことを検証します。
    ///
    /// 責務: legacy欠落を含むmanifestを新規GRDB保存対象から拒否します。
    /// - Parameter manifest: 検証するmanifest。
    /// - Throws: 必須field欠落時は `.unavailable`。
    private func validateComplete(manifest: ConnectionSessionAcquisitionManifest) throws {
        guard manifest.manifestVersion != nil,
              manifest.applicationVersion != nil,
              manifest.schemaContractVersion != nil,
              manifest.pollingPolicyVersion != nil,
              manifest.orderedRequestedPIDs != nil,
              manifest.acquisitionPlatform != nil,
              manifest.modelInputManifestVersion != nil else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        for definition in manifest.pidDefinitions {
            _ = try pidDefinitionRecord(definition, sessionID: "validation")
        }
    }

    /// sessionのRaw境界行を開始、終了順で取得します。
    ///
    /// 責務: 1件のsessionに属する境界recordを安定event順へ並べます。
    /// - Parameters:
    ///   - sessionID: 読取対象の接続セッションID。
    ///   - database: 現在のSQLite読取境界。
    /// - Returns: `started`、`ended` の順に並ぶrecord配列。
    /// - Throws: SQLite読取失敗時のGRDBエラー。
    private func boundaryRecords(
        sessionID: ConnectionSessionID,
        database: Database
    ) throws -> [ConnectionSessionAcquisitionRawBoundaryRecord] {
        try ConnectionSessionAcquisitionRawBoundaryRecord.fetchAll(
            database,
            sql: """
                SELECT * FROM connection_session_acquisition_raw_boundaries
                WHERE sessionID = ?
                ORDER BY CASE eventKind WHEN 'started' THEN 0 ELSE 1 END
                """,
            arguments: [databaseKey(for: sessionID)]
        )
    }

    /// DBから読んだRaw境界列のappend-only時系列を検証します。
    ///
    /// 責務: 空列または正しいstarted、任意の後続endedだけを有効な保存状態として許可します。
    /// - Parameter records: event順へ整列済みのRaw境界record列。
    /// - Throws: event種別、reason、個数、時系列が不正な場合は `.unavailable`。
    private func validateBoundarySequence(
        _ records: [ConnectionSessionAcquisitionRawBoundaryRecord]
    ) throws {
        guard !records.isEmpty else {
            return
        }
        guard records.count <= 2,
              records[0].eventKind == "started",
              records[0].endReason == nil else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
        guard records.count == 2 else {
            return
        }
        guard records[1].eventKind == "ended",
              records[1].occurredAtMicroseconds >= records[0].occurredAtMicroseconds,
              let reason = records[1].endReason,
              ConnectionSessionEndReason(rawValue: reason) != nil else {
            throw ConnectionSessionAcquisitionRepositoryError.unavailable
        }
    }

    /// PID snapshotのcanonical並び順を判定します。
    ///
    /// 責務: 2件のPID snapshotをService、PID昇順へ整列する比較結果を返します。
    /// - Parameters:
    ///   - lhs: 左側のPID snapshot。
    ///   - rhs: 右側のPID snapshot。
    /// - Returns: 左側がcanonical順で先なら `true`。
    private func pidDefinitionPrecedes(
        _ lhs: AcquisitionPIDDefinitionSnapshot,
        _ rhs: AcquisitionPIDDefinitionSnapshot
    ) -> Bool {
        (lhs.request.service, lhs.request.pid) < (rhs.request.service, rhs.request.pid)
    }

    /// Domain session IDをDB keyへ変換します。
    ///
    /// 責務: UUID形式のsession IDを小文字の安定SQLite keyへ変換します。
    /// - Parameter sessionID: 変換するDomain session ID。
    /// - Returns: 小文字UUID文字列。
    private func databaseKey(for sessionID: ConnectionSessionID) -> String {
        sessionID.rawValue.uuidString.lowercased()
    }
}

/// canonical比較に用いる完全manifestと開始microsecondの組です。
nonisolated private struct CanonicalAcquisitionStart: Equatable {
    /// PID定義をService/PID順へ正規化した完全manifestです。
    let manifest: ConnectionSessionAcquisitionManifest
    /// Unix epochからの開始microsecondです。
    let startedAtMicroseconds: Int64
}
