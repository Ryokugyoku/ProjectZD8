import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// file-backed synthetic SQLiteで取得証拠保存の性能、容量、原子性を検証します。
final class GRDBAcquisitionEvidenceSyntheticMeasurementTests: XCTestCase {
    /// 明示実行時だけfull workload matrixを測定してJSONへ保存します。
    ///
    /// 責務: Phase 4Fの全synthetic組合せを独立fixtureで反復測定します。
    /// - Throws: fixture作成、保存、整合性検査、または結果出力に失敗した場合のエラー。
    func testFullSyntheticMeasurementMatrixWhenRequested() throws {
        let markerPath = "/tmp/ProjectZD8Phase4F/run-full-matrix"
        guard ProcessInfo.processInfo.environment["PHASE4F_RUN_MEASUREMENTS"] == "1"
                || FileManager.default.fileExists(atPath: markerPath) else {
            throw XCTSkip("PHASE4F_RUN_MEASUREMENTS=1 の明示時だけfull matrixを実行します")
        }
        let defaultOutputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectZD8Phase4F", isDirectory: true)
            .appendingPathComponent("phase4f-measurements.json")
        let outputPath = ProcessInfo.processInfo.environment["PHASE4F_OUTPUT_PATH"]
            ?? defaultOutputURL.path
        let runner = Phase4FSyntheticMeasurementRunner()
        let report = try runner.runFullMatrix()
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputURL, options: .atomic)
        XCTAssertFalse(report.measurements.isEmpty)
        XCTAssertTrue(report.measurements.allSatisfy(\.foreignKeyCheckPassed))
        XCTAssertTrue(report.measurements.allSatisfy(\.integrityCheckPassed))
        print("PHASE4F_RESULT_PATH=\(outputURL.path)")
    }

    /// 代表workloadで要求数、responded Raw数、non-responded非生成を確認します。
    ///
    /// 責務: 1、4、8、16要求の各transport構成を期待行数へ対応付けます。
    /// - Throws: file-backed fixtureの作成または保存に失敗した場合のエラー。
    func testRepresentativeWorkloadsProduceExpectedRows() throws {
        let cases: [(Int, Phase4FTransportMix)] = [
            (1, .responded100),
            (4, .responded75TimedOut25),
            (8, .responded50MixedFailures),
            (16, .partialBatch)
        ]
        for (requestCount, mix) in cases {
            let result = try Phase4FSyntheticMeasurementRunner().runSingleValidationWorkload(
                requestCount: requestCount,
                transportMix: mix
            )
            XCTAssertEqual(result.batchRows, 1)
            XCTAssertEqual(result.requestRows, requestCount)
            XCTAssertEqual(result.rawRows, result.respondedCount)
            XCTAssertEqual(result.nonRespondedCount, result.dispatchedCount - result.respondedCount)
            XCTAssertTrue(result.sequenceIsContiguous)
            XCTAssertTrue(result.summaryMatchesRawRows)
            XCTAssertTrue(result.foreignKeyCheckPassed)
            XCTAssertTrue(result.integrityCheckPassed)
        }
    }

    /// 100 batch連続保存後のcanonical readbackとRaw sequenceを検証します。
    ///
    /// 責務: 連続batch保存がordinal、sequence、session Raw集計を欠落なく維持することを確認します。
    /// - Throws: file-backed fixtureの作成、保存、またはreadbackに失敗した場合のエラー。
    func testHundredBatchesPreserveCanonicalReadbackAndSequenceContinuity() throws {
        let result = try Phase4FSyntheticMeasurementRunner().runValidationWorkload(
            batchCount: 100,
            requestCount: 8,
            transportMix: .responded75TimedOut25,
            valueOutcome: .decodedValid,
            payloadSize: 256
        )
        XCTAssertEqual(result.batchRows, 100)
        XCTAssertEqual(result.requestRows, 800)
        XCTAssertEqual(result.rawRows, 600)
        XCTAssertEqual(result.canonicalBatchCount, 100)
        XCTAssertTrue(result.sequenceIsContiguous)
        XCTAssertTrue(result.summaryMatchesRawRows)
        XCTAssertTrue(result.foreignKeyCheckPassed)
        XCTAssertTrue(result.integrityCheckPassed)
    }

    /// exact retryとconflict retryの行数およびfile size不変性を検証します。
    ///
    /// 責務: retry判定が追加Raw、request、DB/WAL/SHM増分、既存値変更を生じないことを確認します。
    /// - Throws: file-backed fixtureの作成、保存、またはsize取得に失敗した場合のエラー。
    func testRetriesDoNotAddRowsOrFileCapacity() throws {
        let fixture = try Phase4FRepositoryFixture(requestCount: 1)
        let batch = try fixture.openBatch(ordinal: 0, requestCount: 1)
        try fixture.acquisition.beginBatch(batch, for: fixture.session.id)
        try fixture.acquisition.markRequestDispatchBegun(
            requestOrdinal: 0,
            in: batch.identity,
            for: fixture.session.id
        )
        let observation = fixture.observation(batchOrdinal: 0, requestOrdinal: 0, payloadSize: 256)
        _ = try fixture.acquisition.saveRespondedRequest(
            observation: observation,
            valueOutcome: .decodedValid,
            elapsedNanoseconds: 100,
            reasonCode: nil,
            requestOrdinal: 0,
            in: batch.identity,
            for: fixture.session.id
        )
        let before = try fixture.snapshot()

        XCTAssertThrowsError(
            try fixture.acquisition.saveRespondedRequest(
                observation: observation,
                valueOutcome: .decodedValid,
                elapsedNanoseconds: 100,
                reasonCode: nil,
                requestOrdinal: 0,
                in: batch.identity,
                for: fixture.session.id
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate)
        }
        XCTAssertThrowsError(
            try fixture.acquisition.saveRespondedRequest(
                observation: fixture.observation(batchOrdinal: 0, requestOrdinal: 0, payloadSize: 257),
                valueOutcome: .decodedValid,
                elapsedNanoseconds: 100,
                reasonCode: nil,
                requestOrdinal: 0,
                in: batch.identity,
                for: fixture.session.id
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }

        XCTAssertEqual(try fixture.snapshot(), before)
    }

    /// 5種類のfailure injectionでtransaction rollback後の状態を検証します。
    ///
    /// 責務: Raw、request、canonical readback、batch seal失敗が部分保存を残さないことを確認します。
    /// - Throws: trigger作成、failure実行、または整合性検査に失敗した場合のエラー。
    func testFailureInjectionsPreservePretransactionState() throws {
        for failure in Phase4FRollbackFailure.allCases {
            let fixture = try Phase4FRepositoryFixture(requestCount: 1)
            let open = try fixture.openBatch(ordinal: 0, requestCount: 1)
            try fixture.acquisition.beginBatch(open, for: fixture.session.id)
            try fixture.acquisition.markRequestDispatchBegun(
                requestOrdinal: 0,
                in: open.identity,
                for: fixture.session.id
            )
            if failure == .batchSeal {
                _ = try fixture.saveResponded(batchOrdinal: 0, requestOrdinal: 0, payloadSize: 8)
            }
            try fixture.installFailure(failure)
            let before = try fixture.logicalSnapshot()

            switch failure {
            case .rawInsert, .requestTerminalUpdate, .canonicalRawReadback, .canonicalRequestReadback:
                XCTAssertThrowsError(
                    try fixture.saveResponded(batchOrdinal: 0, requestOrdinal: 0, payloadSize: 8),
                    "failure=\(failure.rawValue)"
                )
            case .batchSeal:
                let storedRequests = try fixture.acquisition.batches(for: fixture.session.id)[0].requests
                let terminal = try fixture.terminalBatch(
                    ordinal: 0,
                    requests: storedRequests,
                    completionState: .completed,
                    failure: nil
                )
                XCTAssertThrowsError(
                    try fixture.acquisition.finishBatch(terminal, for: fixture.session.id),
                    "failure=\(failure.rawValue)"
                )
            }

            XCTAssertEqual(try fixture.logicalSnapshot(), before, "failure=\(failure.rawValue)")
            let integrity = try fixture.integrity()
            XCTAssertTrue(integrity.foreignKeyCheckPassed, "failure=\(failure.rawValue)")
            XCTAssertTrue(integrity.integrityCheckPassed, "failure=\(failure.rawValue)")
            try fixture.removeFailure(failure)
            switch failure {
            case .rawInsert, .requestTerminalUpdate, .canonicalRawReadback, .canonicalRequestReadback:
                let retry = try fixture.saveResponded(
                    batchOrdinal: 0,
                    requestOrdinal: 0,
                    payloadSize: 8
                )
                XCTAssertEqual(retry.transportOutcome, .responded)
                XCTAssertEqual(try fixture.logicalSnapshot().rawRows, 1)
            case .batchSeal:
                let storedRequests = try fixture.acquisition.batches(for: fixture.session.id)[0].requests
                let terminal = try fixture.terminalBatch(
                    ordinal: 0,
                    requests: storedRequests,
                    completionState: .completed,
                    failure: nil
                )
                try fixture.acquisition.finishBatch(terminal, for: fixture.session.id)
                XCTAssertEqual(
                    try fixture.acquisition.batches(for: fixture.session.id)[0].completionState,
                    .completed
                )
            }
        }
    }

    /// percentile集計が小標本でも決定的であることを検証します。
    ///
    /// 責務: median、nearest-rank p95、最小、最大を入力順に依存しない値へ固定します。
    func testStatisticsAreDeterministicForSmallSamplesAndInputOrder() {
        let forward = Phase4FStatistics(values: [4, 1, 3, 2])
        let reverse = Phase4FStatistics(values: [2, 3, 1, 4])
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.median, 2.5)
        XCTAssertEqual(forward.p95, 4)
        XCTAssertEqual(forward.minimum, 1)
        XCTAssertEqual(forward.maximum, 4)
        XCTAssertEqual(Phase4FStatistics(values: [7]).median, 7)
        XCTAssertEqual(Phase4FStatistics(values: [7]).p95, 7)
    }
}

/// Phase 4Fで比較する永続化経路です。
private enum Phase4FStrategy: String, Codable, CaseIterable {
    /// 既存Raw-only append経路です。
    case rawOnlyBaseline
    /// batch表、request evidence表、既存Raw FKを使用する方式Bです。
    case acquisitionEvidenceB
}

/// synthetic transport結果の構成です。
private enum Phase4FTransportMix: String, Codable, CaseIterable {
    /// 全要求がrespondedです。
    case responded100
    /// 4件単位で3件responded、1件timedOutです。
    case responded75TimedOut25
    /// 半数responded、残りを4種類の非respondedへ巡回配分します。
    case responded50MixedFailures
    /// 後半要求を未dispatchのまま残すpartial batchです。
    case partialBatch
}

/// synthetic payload負荷の区分です。
private enum Phase4FPayloadProfile: String, Codable, CaseIterable {
    /// 8 byte固定payloadです。
    case small
    /// 256 byte固定payloadです。
    case medium
    /// 実車応答長を主張しない4,096 byteのSQLite負荷候補です。
    case upperCandidate

    /// profileに対応するbyte数です。
    var byteCount: Int {
        switch self {
        case .small: 8
        case .medium: 256
        case .upperCandidate: 4_096
        }
    }
}

/// rollback測定で注入する永続化失敗です。
private enum Phase4FRollbackFailure: String, CaseIterable {
    /// Raw insertを拒否します。
    case rawInsert
    /// request terminal updateを拒否します。
    case requestTerminalUpdate
    /// insert後Rawを改変してcanonical readbackを不一致にします。
    case canonicalRawReadback
    /// terminal update後requestを削除してcanonical readbackを不一致にします。
    case canonicalRequestReadback
    /// batch seal updateを拒否します。
    case batchSeal
}

/// 反復測定値の順序非依存統計です。
private struct Phase4FStatistics: Codable, Equatable {
    /// 反復回数です。
    let count: Int
    /// 中央値です。
    let median: Double
    /// nearest-rank方式の95 percentileです。
    let p95: Double
    /// 最小値です。
    let minimum: Double
    /// 最大値です。
    let maximum: Double

    /// 入力を昇順化して決定的な要約へ変換します。
    ///
    /// 責務: 有限標本を入力順に依存しないmedianとnearest-rank p95へ集約します。
    /// - Parameter values: 1件以上の測定値。空配列は全値0として扱います。
    init(values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        guard let first = sorted.first, let last = sorted.last else {
            median = 0
            p95 = 0
            minimum = 0
            maximum = 0
            return
        }
        minimum = first
        maximum = last
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        let rank = max(1, Int(ceil(Double(sorted.count) * 0.95)))
        p95 = sorted[rank - 1]
    }
}

/// SQLite本体、WAL、SHMのfile sizeです。
private struct Phase4FFileSizes: Codable, Equatable {
    /// SQLite本体のbyte数です。
    let database: Int64
    /// WALのbyte数です。
    let wal: Int64
    /// SHMのbyte数です。
    let shm: Int64

    /// 3 fileの合計byte数です。
    var total: Int64 { database + wal + shm }

    /// 測定前後の差分を返します。
    ///
    /// 責務: 同じfixture pathの後値から前値をfile別に減算します。
    /// - Parameter earlier: 測定前size。
    /// - Returns: DB、WAL、SHM別の増減byte数。
    func subtracting(_ earlier: Phase4FFileSizes) -> Phase4FFileSizes {
        Phase4FFileSizes(
            database: database - earlier.database,
            wal: wal - earlier.wal,
            shm: shm - earlier.shm
        )
    }
}

/// 1 fixture反復のwall-clockと容量結果です。
private struct Phase4FRepetition: Codable {
    /// 1 batch当たりnanosecondです。
    let nanosecondsPerBatch: Double
    /// 1 request当たりnanosecondです。
    let nanosecondsPerRequest: Double
    /// 測定前file sizeです。
    let before: Phase4FFileSizes
    /// 測定後file sizeです。
    let after: Phase4FFileSizes
    /// 測定前後のfile別増分です。
    let delta: Phase4FFileSizes
}

/// 1 workload組合せの反復集計です。
private struct Phase4FMeasurement: Codable {
    /// 比較経路です。
    let strategy: Phase4FStrategy
    /// batch数です。
    let batchCount: Int
    /// 1 batch当たり要求数です。
    let requestCount: Int
    /// transport構成です。
    let transportMix: Phase4FTransportMix
    /// respondedで保存するvalue outcomeです。
    let valueOutcome: String
    /// payload区分です。
    let payloadProfile: Phase4FPayloadProfile
    /// payload byte数です。
    let payloadBytes: Int
    /// warm-up反復数です。
    let warmupCount: Int
    /// 測定反復数です。
    let repetitionCount: Int
    /// 全batchのresponded件数です。
    let respondedCount: Int
    /// 全batchのnon-responded terminal件数です。
    let nonRespondedCount: Int
    /// 保存後Raw行数です。
    let rawRows: Int
    /// 保存後request evidence行数です。
    let requestRows: Int
    /// 成功transaction数です。
    let successfulTransactions: Int
    /// このworkloadで注入したrollback数です。
    let rollbackCaseCount: Int
    /// batch当たり時間統計です。
    let nanosecondsPerBatch: Phase4FStatistics
    /// request当たり時間統計です。
    let nanosecondsPerRequest: Phase4FStatistics
    /// 1 batch当たり合計file増分の中央値です。
    let approximateBytesPerBatchMedian: Double
    /// 各反復の生測定です。
    let repetitions: [Phase4FRepetition]
    /// 外部キー検査結果です。
    let foreignKeyCheckPassed: Bool
    /// integrity検査結果です。
    let integrityCheckPassed: Bool
    /// session Raw summaryとRaw実集計の一致です。
    let summaryMatchesRawRows: Bool
    /// Raw sequenceの0始まり連続性です。
    let sequenceIsContiguous: Bool
}

/// Phase 4F full matrixの機械可読結果です。
private struct Phase4FMeasurementReport: Codable {
    /// fixtureがsynthetic専用であることの注記です。
    let evidenceBoundary: String
    /// payload上限候補の意味です。
    let payloadBoundary: String
    /// percentile方式です。
    let percentileMethod: String
    /// full matrixの測定結果です。
    let measurements: [Phase4FMeasurement]
}

/// 期待行数と整合性を返すvalidation結果です。
private struct Phase4FValidationResult {
    /// batch行数です。
    let batchRows: Int
    /// request行数です。
    let requestRows: Int
    /// Raw行数です。
    let rawRows: Int
    /// responded数です。
    let respondedCount: Int
    /// non-responded terminal数です。
    let nonRespondedCount: Int
    /// dispatch済み数です。
    let dispatchedCount: Int
    /// canonical batch数です。
    let canonicalBatchCount: Int
    /// Raw sequence連続性です。
    let sequenceIsContiguous: Bool
    /// session Raw summary一致です。
    let summaryMatchesRawRows: Bool
    /// foreign key検査結果です。
    let foreignKeyCheckPassed: Bool
    /// integrity検査結果です。
    let integrityCheckPassed: Bool
}

/// Phase 4F workloadを独立file-backed fixtureで実行します。
private struct Phase4FSyntheticMeasurementRunner {
    /// full matrixをwarm-up後に複数回測定します。
    ///
    /// 責務: 全要求数、batch数、transport、value、payload軸をA/B両経路の反復結果へ変換します。
    /// - Returns: JSON保存可能なfull matrix report。
    /// - Throws: いずれかのfixture測定または整合性検査に失敗した場合のエラー。
    func runFullMatrix() throws -> Phase4FMeasurementReport {
        var measurements: [Phase4FMeasurement] = []
        for strategy in Phase4FStrategy.allCases {
            for batchCount in [1, 100] {
                for requestCount in [1, 4, 8, 16] {
                    for transportMix in Phase4FTransportMix.allCases {
                        for valueOutcome in valueOutcomes {
                            for payloadProfile in Phase4FPayloadProfile.allCases {
                                let repetitionCount = batchCount == 1 ? 5 : 3
                                _ = try measureOnce(
                                    strategy: strategy,
                                    batchCount: batchCount,
                                    requestCount: requestCount,
                                    transportMix: transportMix,
                                    valueOutcome: valueOutcome,
                                    payloadSize: payloadProfile.byteCount
                                )
                                let samples = try (0..<repetitionCount).map { _ in
                                    try measureOnce(
                                        strategy: strategy,
                                        batchCount: batchCount,
                                        requestCount: requestCount,
                                        transportMix: transportMix,
                                        valueOutcome: valueOutcome,
                                        payloadSize: payloadProfile.byteCount
                                    )
                                }
                                measurements.append(makeMeasurement(
                                    strategy: strategy,
                                    batchCount: batchCount,
                                    requestCount: requestCount,
                                    transportMix: transportMix,
                                    valueOutcome: valueOutcome,
                                    payloadProfile: payloadProfile,
                                    samples: samples
                                ))
                            }
                        }
                    }
                }
            }
        }
        return Phase4FMeasurementReport(
            evidenceBoundary: "file-backed synthetic SQLite only; not device, battery, adapter, vehicle, CloudKit, TestFlight, or hosted CI evidence",
            payloadBoundary: "4096 bytes is a synthetic SQLite stress candidate, not a claimed vehicle response length",
            percentileMethod: "nearest-rank p95 after ascending sort; median averages the two center values for even samples",
            measurements: measurements
        )
    }

    /// 1 batchの代表workloadを方式Bで実行します。
    ///
    /// 責務: 要求数とtransport構成を期待行数検証用のfile-backed結果へ変換します。
    /// - Parameters:
    ///   - requestCount: batch要求数。
    ///   - transportMix: transport結果構成。
    /// - Returns: 行数と整合性のvalidation結果。
    /// - Throws: fixture保存または検査に失敗した場合のエラー。
    func runSingleValidationWorkload(
        requestCount: Int,
        transportMix: Phase4FTransportMix
    ) throws -> Phase4FValidationResult {
        try runValidationWorkload(
            batchCount: 1,
            requestCount: requestCount,
            transportMix: transportMix,
            valueOutcome: .decodedValid,
            payloadSize: 8
        )
    }

    /// 指定方式B workloadを行数検証用に1回実行します。
    ///
    /// 責務: 連続batch workloadをcanonical行数と整合性結果へ変換します。
    /// - Parameters:
    ///   - batchCount: 保存するbatch数。
    ///   - requestCount: 1 batchの要求数。
    ///   - transportMix: transport構成。
    ///   - valueOutcome: respondedの値結果。
    ///   - payloadSize: synthetic payload byte数。
    /// - Returns: 保存後validation結果。
    /// - Throws: fixture保存または検査に失敗した場合のエラー。
    func runValidationWorkload(
        batchCount: Int,
        requestCount: Int,
        transportMix: Phase4FTransportMix,
        valueOutcome: PIDRequestValueOutcome,
        payloadSize: Int
    ) throws -> Phase4FValidationResult {
        let fixture = try Phase4FRepositoryFixture(requestCount: requestCount)
        for batchOrdinal in 0..<batchCount {
            _ = try persistEvidenceBatch(
                fixture: fixture,
                batchOrdinal: batchOrdinal,
                requestCount: requestCount,
                transportMix: transportMix,
                valueOutcome: valueOutcome,
                payloadSize: payloadSize
            )
        }
        let logical = try fixture.logicalSnapshot()
        let integrity = try fixture.integrity()
        let plan = outcomePlan(requestCount: requestCount, mix: transportMix)
        return Phase4FValidationResult(
            batchRows: logical.batchRows,
            requestRows: logical.requestRows,
            rawRows: logical.rawRows,
            respondedCount: plan.filter { $0 == .responded }.count * batchCount,
            nonRespondedCount: plan.compactMap { $0 }.filter { $0 != .responded }.count * batchCount,
            dispatchedCount: plan.compactMap { $0 }.count * batchCount,
            canonicalBatchCount: try fixture.acquisition.batches(for: fixture.session.id).count,
            sequenceIsContiguous: logical.sequenceIsContiguous,
            summaryMatchesRawRows: logical.summaryMatchesRawRows,
            foreignKeyCheckPassed: integrity.foreignKeyCheckPassed,
            integrityCheckPassed: integrity.integrityCheckPassed
        )
    }

    /// 1独立fixtureのwall-clockとsizeを測定します。
    ///
    /// 責務: 指定workloadを準備済みDBの前後snapshotと経過時間へ変換します。
    /// - Parameters:
    ///   - strategy: 比較する保存経路。
    ///   - batchCount: batch数。
    ///   - requestCount: batch要求数。
    ///   - transportMix: transport構成。
    ///   - valueOutcome: responded値結果。
    ///   - payloadSize: synthetic payload byte数。
    /// - Returns: 1反復の測定結果と論理検査値。
    /// - Throws: fixture保存または検査に失敗した場合のエラー。
    private func measureOnce(
        strategy: Phase4FStrategy,
        batchCount: Int,
        requestCount: Int,
        transportMix: Phase4FTransportMix,
        valueOutcome: PIDRequestValueOutcome,
        payloadSize: Int
    ) throws -> Phase4FMeasuredSample {
        let fixture = try Phase4FRepositoryFixture(requestCount: requestCount)
        let before = try fixture.fileSizes()
        let started = DispatchTime.now().uptimeNanoseconds
        var successfulTransactions = 0
        for batchOrdinal in 0..<batchCount {
            switch strategy {
            case .rawOnlyBaseline:
                successfulTransactions += try persistRawOnlyBatch(
                    fixture: fixture,
                    batchOrdinal: batchOrdinal,
                    requestCount: requestCount,
                    transportMix: transportMix,
                    payloadSize: payloadSize
                )
            case .acquisitionEvidenceB:
                successfulTransactions += try persistEvidenceBatch(
                    fixture: fixture,
                    batchOrdinal: batchOrdinal,
                    requestCount: requestCount,
                    transportMix: transportMix,
                    valueOutcome: valueOutcome,
                    payloadSize: payloadSize
                )
            }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let after = try fixture.fileSizes()
        let logical = try fixture.logicalSnapshot()
        let integrity = try fixture.integrity()
        return Phase4FMeasuredSample(
            elapsedNanoseconds: elapsed,
            before: before,
            after: after,
            logical: logical,
            integrity: integrity,
            successfulTransactions: successfulTransactions
        )
    }

    /// 方式Aでresponded分だけ既存Raw appendへ保存します。
    ///
    /// 責務: transport構成からrespondedだけをRaw-only baseline transactionへ変換します。
    /// - Parameters:
    ///   - fixture: 保存先fixture。
    ///   - batchOrdinal: synthetic batch位置。
    ///   - requestCount: 要求数。
    ///   - transportMix: transport構成。
    ///   - payloadSize: payload byte数。
    /// - Returns: 成功したRaw append transaction数。
    /// - Throws: Raw appendに失敗した場合のエラー。
    private func persistRawOnlyBatch(
        fixture: Phase4FRepositoryFixture,
        batchOrdinal: Int,
        requestCount: Int,
        transportMix: Phase4FTransportMix,
        payloadSize: Int
    ) throws -> Int {
        let plan = outcomePlan(requestCount: requestCount, mix: transportMix)
        var transactions = 0
        for requestOrdinal in 0..<requestCount where plan[requestOrdinal] == .responded {
            try fixture.sessions.append(
                fixture.observation(
                    batchOrdinal: batchOrdinal,
                    requestOrdinal: requestOrdinal,
                    payloadSize: payloadSize
                ),
                to: fixture.session.id
            )
            transactions += 1
        }
        return transactions
    }

    /// 方式Bでbatch intentからterminal sealまで保存します。
    ///
    /// 責務: 1 batchの選択、dispatch、terminal、sealを方式B repository操作へ変換します。
    /// - Parameters:
    ///   - fixture: 保存先fixture。
    ///   - batchOrdinal: session内batch位置。
    ///   - requestCount: 要求数。
    ///   - transportMix: transport構成。
    ///   - valueOutcome: responded値結果。
    ///   - payloadSize: payload byte数。
    /// - Returns: 成功したrepository transaction数。
    /// - Throws: batchまたはrequest保存に失敗した場合のエラー。
    private func persistEvidenceBatch(
        fixture: Phase4FRepositoryFixture,
        batchOrdinal: Int,
        requestCount: Int,
        transportMix: Phase4FTransportMix,
        valueOutcome: PIDRequestValueOutcome,
        payloadSize: Int
    ) throws -> Int {
        let open = try fixture.openBatch(ordinal: batchOrdinal, requestCount: requestCount)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)
        var transactions = 1
        var requests = open.requests
        let plan = outcomePlan(requestCount: requestCount, mix: transportMix)
        for requestOrdinal in 0..<requestCount {
            guard let outcome = plan[requestOrdinal] else { continue }
            try fixture.acquisition.markRequestDispatchBegun(
                requestOrdinal: requestOrdinal,
                in: open.identity,
                for: fixture.session.id
            )
            transactions += 1
            if outcome == .responded {
                requests[requestOrdinal] = try fixture.acquisition.saveRespondedRequest(
                    observation: fixture.observation(
                        batchOrdinal: batchOrdinal,
                        requestOrdinal: requestOrdinal,
                        payloadSize: payloadSize
                    ),
                    valueOutcome: valueOutcome,
                    elapsedNanoseconds: UInt64(requestOrdinal + 1) * 100,
                    reasonCode: nil,
                    requestOrdinal: requestOrdinal,
                    in: open.identity,
                    for: fixture.session.id
                )
            } else {
                requests[requestOrdinal] = try fixture.acquisition.saveNonRespondedRequest(
                    outcome: outcome,
                    elapsedNanoseconds: UInt64(requestOrdinal + 1) * 100,
                    reasonCode: "synthetic_\(outcome.rawValue)",
                    requestOrdinal: requestOrdinal,
                    in: open.identity,
                    for: fixture.session.id
                )
            }
            transactions += 1
        }
        let terminal = try fixture.terminalBatchForPlan(
            ordinal: batchOrdinal,
            requests: requests,
            transportMix: transportMix
        )
        try fixture.acquisition.finishBatch(terminal, for: fixture.session.id)
        return transactions + 1
    }

    /// transport mixをrequest別のterminalまたは未dispatchへ展開します。
    ///
    /// 責務: 割合定義を要求順に対して決定的な排他結果列へ変換します。
    /// - Parameters:
    ///   - requestCount: 要求数。
    ///   - mix: transport構成。
    /// - Returns: `nil`を未dispatchとする要求順結果列。
    private func outcomePlan(
        requestCount: Int,
        mix: Phase4FTransportMix
    ) -> [PIDRequestTransportOutcome?] {
        (0..<requestCount).map { ordinal in
            switch mix {
            case .responded100:
                return .responded
            case .responded75TimedOut25:
                return ordinal % 4 == 3 ? .timedOut : .responded
            case .responded50MixedFailures:
                guard ordinal < (requestCount + 1) / 2 else {
                    let failures: [PIDRequestTransportOutcome] = [
                        .timedOut, .cancelled, .transportFailure, .unclassifiedResponse
                    ]
                    return failures[(ordinal - (requestCount + 1) / 2) % failures.count]
                }
                return .responded
            case .partialBatch:
                guard ordinal < (requestCount + 1) / 2 else { return nil }
                return ordinal.isMultiple(of: 2) ? .responded : .timedOut
            }
        }
    }

    /// 反復sample列を1 workloadの統計へ集約します。
    ///
    /// 責務: 同一workload反復を時間、容量、行数、整合性の要約へ変換します。
    /// - Parameters:
    ///   - strategy: 比較経路。
    ///   - batchCount: batch数。
    ///   - requestCount: 要求数。
    ///   - transportMix: transport構成。
    ///   - valueOutcome: responded値結果。
    ///   - payloadProfile: payload区分。
    ///   - samples: warm-upを除く反復値。
    /// - Returns: 1 workloadの集計結果。
    private func makeMeasurement(
        strategy: Phase4FStrategy,
        batchCount: Int,
        requestCount: Int,
        transportMix: Phase4FTransportMix,
        valueOutcome: PIDRequestValueOutcome,
        payloadProfile: Phase4FPayloadProfile,
        samples: [Phase4FMeasuredSample]
    ) -> Phase4FMeasurement {
        let plan = outcomePlan(requestCount: requestCount, mix: transportMix)
        let repetitions = samples.map { sample in
            let delta = sample.after.subtracting(sample.before)
            return Phase4FRepetition(
                nanosecondsPerBatch: Double(sample.elapsedNanoseconds) / Double(batchCount),
                nanosecondsPerRequest: Double(sample.elapsedNanoseconds) / Double(batchCount * requestCount),
                before: sample.before,
                after: sample.after,
                delta: delta
            )
        }
        let last = samples.last!
        return Phase4FMeasurement(
            strategy: strategy,
            batchCount: batchCount,
            requestCount: requestCount,
            transportMix: transportMix,
            valueOutcome: valueOutcome.rawValue,
            payloadProfile: payloadProfile,
            payloadBytes: payloadProfile.byteCount,
            warmupCount: 1,
            repetitionCount: samples.count,
            respondedCount: plan.filter { $0 == .responded }.count * batchCount,
            nonRespondedCount: plan.compactMap { $0 }.filter { $0 != .responded }.count * batchCount,
            rawRows: last.logical.rawRows,
            requestRows: last.logical.requestRows,
            successfulTransactions: last.successfulTransactions,
            rollbackCaseCount: 0,
            nanosecondsPerBatch: Phase4FStatistics(values: repetitions.map(\.nanosecondsPerBatch)),
            nanosecondsPerRequest: Phase4FStatistics(values: repetitions.map(\.nanosecondsPerRequest)),
            approximateBytesPerBatchMedian: Phase4FStatistics(
                values: repetitions.map { Double($0.delta.total) / Double(batchCount) }
            ).median,
            repetitions: repetitions,
            foreignKeyCheckPassed: samples.allSatisfy(\.integrity.foreignKeyCheckPassed),
            integrityCheckPassed: samples.allSatisfy(\.integrity.integrityCheckPassed),
            summaryMatchesRawRows: samples.allSatisfy(\.logical.summaryMatchesRawRows),
            sequenceIsContiguous: samples.allSatisfy(\.logical.sequenceIsContiguous)
        )
    }

    /// respondedで使用する全value outcomeです。
    private var valueOutcomes: [PIDRequestValueOutcome] {
        [.notEvaluated, .decodedValid, .decodeFailure, .invalidValue]
    }
}

/// 1回の内部測定値です。
private struct Phase4FMeasuredSample {
    /// workload経過nanosecondです。
    let elapsedNanoseconds: UInt64
    /// 測定前file sizeです。
    let before: Phase4FFileSizes
    /// 測定後file sizeです。
    let after: Phase4FFileSizes
    /// 保存後論理snapshotです。
    let logical: Phase4FLogicalSnapshot
    /// 保存後integrity結果です。
    let integrity: Phase4FIntegrity
    /// 成功transaction数です。
    let successfulTransactions: Int
}

/// rollback前後で比較するSQLite論理状態です。
private struct Phase4FLogicalSnapshot: Equatable {
    /// batch行数です。
    let batchRows: Int
    /// request行数です。
    let requestRows: Int
    /// Raw行数です。
    let rawRows: Int
    /// session集計Raw件数です。
    let summaryRecordCount: Int64
    /// session集計payload byte数です。
    let summaryByteCount: Int64
    /// Raw実payload byte数です。
    let actualByteCount: Int64
    /// request状態を安定順で連結した値です。
    let requestState: [String]
    /// batch状態を安定順で連結した値です。
    let batchState: [String]
    /// Raw sequenceです。
    let sequences: [Int64]

    /// session集計とRaw実行数・byte数の一致です。
    var summaryMatchesRawRows: Bool {
        summaryRecordCount == rawRows && summaryByteCount == actualByteCount
    }

    /// Raw sequenceが0から連続するかを示します。
    var sequenceIsContiguous: Bool {
        sequences == Array(0..<Int64(sequences.count))
    }
}

/// SQLite整合性検査の結果です。
private struct Phase4FIntegrity {
    /// foreign key違反が0件です。
    let foreignKeyCheckPassed: Bool
    /// integrity checkがokです。
    let integrityCheckPassed: Bool
}

/// 方式A/Bが共有する独立file-backed synthetic repository fixtureです。
private final class Phase4FRepositoryFixture {
    /// fixture root directoryです。
    private let directoryURL: URL
    /// SQLite本体URLです。
    private let databaseURL: URL
    /// 全repositoryが共有するfile-backed Queueです。
    let queue: DatabaseQueue
    /// Raw-only baseline repositoryです。
    let sessions: GRDBConnectionSessionRepository
    /// 方式B repositoryです。
    let acquisition: GRDBConnectionSessionAcquisitionRepository
    /// synthetic親sessionです。
    let session: ConnectionSession
    /// manifestで使用するsynthetic要求列です。
    private let requests: [OBDPIDRequest]

    /// `/tmp`配下に専用DB、session、manifestを作成します。
    ///
    /// 責務: 指定要求数の方式A/B比較を同一schema初期状態へ固定します。
    /// - Parameter requestCount: manifestへ保存するsynthetic要求数。
    /// - Throws: directory、DB、migration、親aggregate作成に失敗した場合のエラー。
    init(requestCount: Int) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectZD8Phase4F-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directoryURL = root
        databaseURL = root.appendingPathComponent("fixture.sqlite")
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            _ = try String.fetchOne(database, sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        session = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID()),
            accountIdentifier: "phase4f-synthetic-account",
            startedAt: Date(timeIntervalSince1970: 1)
        )
        requests = (0..<requestCount).map { ordinal in
            OBDPIDRequest(service: 240, pid: UInt8(ordinal))
        }
        try sessions.save(session)
        try acquisition.saveStartOnce(
            manifest: try Self.makeManifest(requests: requests),
            startedAt: Date(timeIntervalSince1970: 2),
            for: session.id
        )
    }

    /// fixture directoryを削除します。
    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// selected-only要求を持つopen batchを生成します。
    ///
    /// 責務: 指定ordinalと要求数を決定的なopen batch evidenceへ変換します。
    /// - Parameters:
    ///   - ordinal: session内batch ordinal。
    ///   - requestCount: 先頭から選択する要求数。
    /// - Returns: policy評価完了済みopen batch。
    /// - Throws: Domain不変条件違反。
    func openBatch(ordinal: Int, requestCount: Int) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: Int64(ordinal)),
            generation: 1,
            policyTick: UInt(ordinal),
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10 + Double(ordinal) * 2),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: try (0..<requestCount).map { requestOrdinal in
                try PIDRequestEvidence(
                    requestOrdinal: requestOrdinal,
                    manifestPIDOrdinal: requestOrdinal,
                    dispatchState: .selectedOnly,
                    transportOutcome: nil,
                    valueOutcome: .notEvaluated,
                    rawSequence: nil,
                    elapsedNanoseconds: nil,
                    reasonCode: nil
                )
            }
        )
    }

    /// synthetic Raw observationを生成します。
    ///
    /// 責務: batch、request、payload sizeを再現可能な未decode Raw入力へ変換します。
    /// - Parameters:
    ///   - batchOrdinal: synthetic batch位置。
    ///   - requestOrdinal: manifest要求位置。
    ///   - payloadSize: payload byte数。
    /// - Returns: 実PIDや実応答長を意味しないsynthetic observation。
    func observation(
        batchOrdinal: Int,
        requestOrdinal: Int,
        payloadSize: Int
    ) -> OBDRawResponseObservation {
        OBDRawResponseObservation(
            observedAt: Date(timeIntervalSince1970: 11 + Double(batchOrdinal) * 2 + Double(requestOrdinal) / 100),
            batchElapsedNanoseconds: UInt64(requestOrdinal + 1) * 100,
            request: requests[requestOrdinal],
            payload: (0..<payloadSize).map { UInt8(($0 + requestOrdinal) % 251) }
        )
    }

    /// responded要求を方式Bへ保存します。
    ///
    /// 責務: failure test用の固定responded入力をrepositoryへ渡します。
    /// - Parameters:
    ///   - batchOrdinal: batch位置。
    ///   - requestOrdinal: request位置。
    ///   - payloadSize: payload byte数。
    /// - Returns: canonical request evidence。
    /// - Throws: repository保存失敗。
    func saveResponded(
        batchOrdinal: Int,
        requestOrdinal: Int,
        payloadSize: Int
    ) throws -> PIDRequestEvidence {
        try acquisition.saveRespondedRequest(
            observation: observation(
                batchOrdinal: batchOrdinal,
                requestOrdinal: requestOrdinal,
                payloadSize: payloadSize
            ),
            valueOutcome: .decodedValid,
            elapsedNanoseconds: UInt64(requestOrdinal + 1) * 100,
            reasonCode: nil,
            requestOrdinal: requestOrdinal,
            in: AcquisitionBatchIdentity(ordinal: Int64(batchOrdinal)),
            for: session.id
        )
    }

    /// transport mixに対応するterminal batchを生成します。
    ///
    /// 責務: request結果列とmixをcompletedまたはfailed batchへ変換します。
    /// - Parameters:
    ///   - ordinal: batch位置。
    ///   - requests: 保存済みrequest列。
    ///   - transportMix: workloadのtransport構成。
    /// - Returns: seal可能なterminal batch。
    /// - Throws: Domain不変条件違反。
    func terminalBatchForPlan(
        ordinal: Int,
        requests: [PIDRequestEvidence],
        transportMix: Phase4FTransportMix
    ) throws -> AcquisitionBatchEvidence {
        let failure: AcquisitionBatchFailure?
        switch transportMix {
        case .responded100:
            failure = nil
        case .responded75TimedOut25, .partialBatch:
            failure = requests.contains(where: { $0.transportOutcome == .timedOut }) || transportMix == .partialBatch
                ? .transportUnavailable : nil
        case .responded50MixedFailures:
            failure = requests.contains(where: { $0.transportOutcome == .cancelled })
                ? .cancelled : .transportUnavailable
        }
        return try terminalBatch(
            ordinal: ordinal,
            requests: requests,
            completionState: failure == nil ? .completed : .failed,
            failure: failure
        )
    }

    /// 明示状態のterminal batchを生成します。
    ///
    /// 責務: failure injection用の要求列を指定されたbatch終端へ変換します。
    /// - Parameters:
    ///   - ordinal: batch位置。
    ///   - requests: request evidence列。
    ///   - completionState: batch終端状態。
    ///   - failure: batch failure。
    /// - Returns: terminal batch evidence。
    /// - Throws: Domain不変条件違反。
    func terminalBatch(
        ordinal: Int,
        requests: [PIDRequestEvidence],
        completionState: AcquisitionBatchCompletionState,
        failure: AcquisitionBatchFailure?
    ) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: Int64(ordinal)),
            generation: 1,
            policyTick: UInt(ordinal),
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10 + Double(ordinal) * 2),
            completionState: completionState,
            completedAt: Date(timeIntervalSince1970: 11 + Double(ordinal) * 2),
            failure: failure,
            requests: requests
        )
    }

    /// rollback用SQLite triggerを追加します。
    ///
    /// 責務: Production分岐を追加せず指定failureを次のrepository transactionへ注入します。
    /// - Parameter failure: 注入する失敗位置。
    /// - Throws: trigger作成に失敗した場合のGRDBエラー。
    func installFailure(_ failure: Phase4FRollbackFailure) throws {
        try queue.write { database in
            let sql: String
            switch failure {
            case .rawInsert:
                sql = """
                    CREATE TRIGGER phase4f_reject_raw BEFORE INSERT ON connection_session_raw_logs
                    BEGIN SELECT RAISE(ABORT, 'phase4f raw insert'); END
                    """
            case .requestTerminalUpdate:
                sql = """
                    CREATE TRIGGER phase4f_reject_request BEFORE UPDATE ON connection_session_acquisition_pid_requests
                    WHEN NEW.dispatchState = 'terminal'
                    BEGIN SELECT RAISE(ABORT, 'phase4f request update'); END
                    """
            case .canonicalRawReadback:
                sql = """
                    CREATE TRIGGER phase4f_corrupt_raw AFTER INSERT ON connection_session_raw_logs
                    BEGIN
                        UPDATE connection_session_raw_logs SET payload = X'FF'
                        WHERE sessionID = NEW.sessionID AND sequence = NEW.sequence;
                    END
                    """
            case .canonicalRequestReadback:
                sql = """
                    CREATE TRIGGER phase4f_remove_request AFTER UPDATE ON connection_session_acquisition_pid_requests
                    WHEN NEW.dispatchState = 'terminal'
                    BEGIN
                        DELETE FROM connection_session_acquisition_pid_requests
                        WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal
                            AND requestOrdinal = NEW.requestOrdinal;
                    END
                    """
            case .batchSeal:
                sql = """
                    CREATE TRIGGER phase4f_reject_batch_seal BEFORE UPDATE ON connection_session_acquisition_batches
                    WHEN NEW.isSealed = 1
                    BEGIN SELECT RAISE(ABORT, 'phase4f batch seal'); END
                    """
            }
            try database.execute(sql: sql)
        }
    }

    /// rollback確認後にtest triggerを除去します。
    ///
    /// 責務: 指定failure injectionだけを解除して同一immutable入力のretryを可能にします。
    /// - Parameter failure: 除去する失敗位置。
    /// - Throws: trigger削除に失敗した場合のGRDBエラー。
    func removeFailure(_ failure: Phase4FRollbackFailure) throws {
        let triggerName: String
        switch failure {
        case .rawInsert:
            triggerName = "phase4f_reject_raw"
        case .requestTerminalUpdate:
            triggerName = "phase4f_reject_request"
        case .canonicalRawReadback:
            triggerName = "phase4f_corrupt_raw"
        case .canonicalRequestReadback:
            triggerName = "phase4f_remove_request"
        case .batchSeal:
            triggerName = "phase4f_reject_batch_seal"
        }
        try queue.write { database in
            try database.execute(sql: "DROP TRIGGER \(triggerName)")
        }
    }

    /// DB、WAL、SHMの現在file sizeを取得します。
    ///
    /// 責務: 1 fixtureの3 SQLite file pathを存在しないfileは0 byteとして測定します。
    /// - Returns: file別size。
    /// - Throws: 存在するfileの属性取得に失敗した場合のエラー。
    func fileSizes() throws -> Phase4FFileSizes {
        try Phase4FFileSizes(
            database: fileSize(atPath: databaseURL.path),
            wal: fileSize(atPath: databaseURL.path + "-wal"),
            shm: fileSize(atPath: databaseURL.path + "-shm")
        )
    }

    /// file sizeを取得します。
    ///
    /// 責務: 指定pathの通常fileをbyte数へ変換し不在時は0を返します。
    /// - Parameter path: 測定するfile path。
    /// - Returns: file byte数、または不在時0。
    /// - Throws: file属性取得に失敗した場合のエラー。
    private func fileSize(atPath path: String) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// file sizeを含むretry比較snapshotを取得します。
    ///
    /// 責務: 論理行状態とDB/WAL/SHM容量を単一比較値へ固定します。
    /// - Returns: retry前後比較snapshot。
    /// - Throws: SQLite読取またはfile属性取得に失敗した場合のエラー。
    func snapshot() throws -> Phase4FRetrySnapshot {
        Phase4FRetrySnapshot(logical: try logicalSnapshot(), files: try fileSizes())
    }

    /// SQLite行とsession Raw集計を安定順で取得します。
    ///
    /// 責務: rollback前後で比較可能な全関連論理状態をcanonical順へ変換します。
    /// - Returns: batch、request、Raw、summaryのsnapshot。
    /// - Throws: SQLite読取に失敗した場合のエラー。
    func logicalSnapshot() throws -> Phase4FLogicalSnapshot {
        try queue.read { database in
            let key = session.id.rawValue.uuidString.lowercased()
            let requestRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT batchOrdinal, requestOrdinal, dispatchState, COALESCE(transportOutcome, ''),
                        valueOutcome, COALESCE(rawSequence, -1), COALESCE(elapsedNanoseconds, -1),
                        COALESCE(reasonCode, ''), isSealed
                    FROM connection_session_acquisition_pid_requests
                    WHERE sessionID = ? ORDER BY batchOrdinal, requestOrdinal
                    """,
                arguments: [key]
            )
            let batchRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT batchOrdinal, COALESCE(completionState, ''), COALESCE(failureCode, ''), isSealed
                    FROM connection_session_acquisition_batches
                    WHERE sessionID = ? ORDER BY batchOrdinal
                    """,
                arguments: [key]
            )
            let summary = try Row.fetchOne(
                database,
                sql: "SELECT rawRecordCount, rawByteCount FROM connection_sessions WHERE id = ?",
                arguments: [key]
            )
            let raw = try Row.fetchOne(
                database,
                sql: "SELECT COUNT(*) AS count, COALESCE(SUM(length(payload)), 0) AS bytes FROM connection_session_raw_logs WHERE sessionID = ?",
                arguments: [key]
            )
            return Phase4FLogicalSnapshot(
                batchRows: batchRows.count,
                requestRows: requestRows.count,
                rawRows: raw?["count"] ?? 0,
                summaryRecordCount: summary?["rawRecordCount"] ?? 0,
                summaryByteCount: summary?["rawByteCount"] ?? 0,
                actualByteCount: raw?["bytes"] ?? 0,
                requestState: requestRows.map { String(describing: $0) },
                batchState: batchRows.map { String(describing: $0) },
                sequences: try Int64.fetchAll(
                    database,
                    sql: "SELECT sequence FROM connection_session_raw_logs WHERE sessionID = ? ORDER BY sequence",
                    arguments: [key]
                )
            )
        }
    }

    /// foreign key checkとintegrity checkを実行します。
    ///
    /// 責務: 1 fixtureの参照整合性とSQLite全体整合性を2つの真偽値へ変換します。
    /// - Returns: 両PRAGMAの合否。
    /// - Throws: PRAGMA実行に失敗した場合のエラー。
    func integrity() throws -> Phase4FIntegrity {
        try queue.read { database in
            Phase4FIntegrity(
                foreignKeyCheckPassed: try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty,
                integrityCheckPassed: try String.fetchOne(database, sql: "PRAGMA integrity_check") == "ok"
            )
        }
    }

    /// synthetic manifestを生成します。
    ///
    /// 責務: 実PID意味を持たない要求列を完全な取得定義snapshotへ変換します。
    /// - Parameter requests: synthetic Service/PID要求列。
    /// - Returns: sealed保存可能なmanifest。
    /// - Throws: Domain不変条件違反。
    private static func makeManifest(
        requests: [OBDPIDRequest]
    ) throws -> ConnectionSessionAcquisitionManifest {
        let definitions = try requests.map { request in
            try AcquisitionPIDDefinitionSnapshot(
                request: request,
                capabilitySupport: .supported,
                isCollectionEnabled: true,
                definitionRevision: 1,
                requiredByteCount: 1,
                definitionIdentity: AcquisitionPIDDefinitionIdentity(
                    canonicalizationVersion: 1,
                    expression: "syntheticByte0"
                ),
                unit: "synthetic-unit",
                validityRange: .notDeclared
            )
        }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(
                marketingVersion: "phase4f-synthetic",
                buildVersion: "1"
            ),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: requests),
            pidDefinitions: definitions,
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }
}

/// retry前後で比較する論理状態とfile容量です。
private struct Phase4FRetrySnapshot: Equatable {
    /// SQLite論理状態です。
    let logical: Phase4FLogicalSnapshot
    /// DB、WAL、SHM容量です。
    let files: Phase4FFileSizes
}
