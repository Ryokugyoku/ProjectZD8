import Foundation
import XCTest
@testable import ProjectZD8

/// 保存先を準備できないときの取得チャンクRepositoryが失敗を成功に潰さないことを検証します。
final class UnavailableConnectionSessionAcquisitionChunkRepositoryTests: XCTestCase {
    /// 空でないチャンクのcommitは `.unavailable` で失敗します。
    ///
    /// 責務: 保存できないRawを保存済みとして扱わず、利用不能を明示することを確認します。
    func testNonEmptyChunkCommitThrowsUnavailable() {
        let raw = ConnectionSessionRawLogEntry(
            sequence: 0,
            observedAt: Date(timeIntervalSince1970: 10),
            batchElapsedNanoseconds: 100,
            service: 1,
            pid: 12,
            payload: [0x1F],
            monotonicNanoseconds: 1_000,
            segmentOrdinal: 0
        )
        let chunk = ConnectionSessionAcquisitionChunk(sessionID: ConnectionSessionID(), rawEntries: [raw], batches: [])

        XCTAssertThrowsError(try UnavailableConnectionSessionAcquisitionChunkRepository().commit(chunk)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionChunkRepositoryError, .unavailable)
        }
    }

    /// 空チャンクのcommitも `.unavailable` で失敗します。
    ///
    /// 責務: 書くものが無い場合でも保存先の利用不能を成功として報告しないことを確認します。
    func testEmptyChunkCommitThrowsUnavailable() {
        let chunk = ConnectionSessionAcquisitionChunk(sessionID: ConnectionSessionID(), rawEntries: [], batches: [])

        XCTAssertThrowsError(try UnavailableConnectionSessionAcquisitionChunkRepository().commit(chunk)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionChunkRepositoryError, .unavailable)
        }
    }
}
