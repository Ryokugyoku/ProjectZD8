import Foundation
import XCTest
@testable import ProjectZD8

/// 取得チャンクが空かどうかの判定を、Rawとbatchの有無の4通りで検証します。
final class ConnectionSessionAcquisitionChunkTests: XCTestCase {
    /// RawもbatchもないチャンクはisEmptyです。
    ///
    /// 責務: 両方0件のときだけ保存を省略してよいと判定することを確認します。
    func testChunkWithoutRawAndBatchIsEmpty() {
        let chunk = ConnectionSessionAcquisitionChunk(sessionID: ConnectionSessionID(), rawEntries: [], batches: [])

        XCTAssertTrue(chunk.isEmpty)
    }

    /// Rawだけを持つチャンクは空ではありません。
    ///
    /// 責務: batchが無くてもRawが1件あれば保存対象と判定することを確認します。
    func testChunkWithOnlyRawIsNotEmpty() {
        let chunk = ConnectionSessionAcquisitionChunk(
            sessionID: ConnectionSessionID(),
            rawEntries: [makeRaw()],
            batches: []
        )

        XCTAssertFalse(chunk.isEmpty)
    }

    /// batchだけを持つチャンクは空ではありません。
    ///
    /// 責務: Rawが無くてもbatchが1件あれば保存対象と判定することを確認します。
    func testChunkWithOnlyBatchIsNotEmpty() throws {
        let chunk = ConnectionSessionAcquisitionChunk(
            sessionID: ConnectionSessionID(),
            rawEntries: [],
            batches: [try makeBatch()]
        )

        XCTAssertFalse(chunk.isEmpty)
    }

    /// Rawとbatchの両方を持つチャンクは空ではありません。
    ///
    /// 責務: 両方が1件以上あるとき保存対象と判定することを確認します。
    func testChunkWithRawAndBatchIsNotEmpty() throws {
        let chunk = ConnectionSessionAcquisitionChunk(
            sessionID: ConnectionSessionID(),
            rawEntries: [makeRaw()],
            batches: [try makeBatch()]
        )

        XCTAssertFalse(chunk.isEmpty)
    }

    /// テスト用のRawを1件生成します。
    ///
    /// 責務: 判定に影響しない既定値を持つRaw entryを返します。
    /// - Returns: 連番0のRaw entry。
    private func makeRaw() -> ConnectionSessionRawLogEntry {
        ConnectionSessionRawLogEntry(
            sequence: 0,
            observedAt: Date(timeIntervalSince1970: 10),
            batchElapsedNanoseconds: 100,
            service: 1,
            pid: 12,
            payload: [0x1F],
            monotonicNanoseconds: 1_000,
            segmentOrdinal: 0
        )
    }

    /// テスト用の未確定batchを1件生成します。
    ///
    /// 責務: requestを持たない最小のbatch証拠を返します。
    /// - Returns: batch番号0のbatch証拠。
    /// - Throws: batch証拠の不変条件違反。
    private func makeBatch() throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: 0),
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: []
        )
    }
}
