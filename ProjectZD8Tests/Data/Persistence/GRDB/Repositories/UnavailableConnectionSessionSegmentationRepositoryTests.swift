import Foundation
import XCTest
@testable import ProjectZD8

/// DB準備不可時の区間・欠損Repositoryが、すべての操作を明示的な利用不能として失敗させることを検証します。
final class UnavailableConnectionSessionSegmentationRepositoryTests: XCTestCase {
    /// 区間の開始・終了・読込はすべて利用不能で失敗します。
    ///
    /// 責務: 区間Repositoryの全メソッドが空データや成功を返さないことを確認します。
    func testSegmentOperationsThrowUnavailable() {
        let repository = UnavailableConnectionSessionSegmentationRepository()
        let sessionID = ConnectionSessionID()
        let segment = ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: Date(timeIntervalSince1970: 1), monotonicAnchorNanoseconds: 1, firstSequence: 0
        )

        assertUnavailable { try repository.beginSegment(segment, for: sessionID) }
        assertUnavailable {
            try repository.finishSegment(ordinal: 0, for: sessionID, endedAt: Date(timeIntervalSince1970: 2), reason: .sessionEnded, lastSequence: nil)
        }
        assertUnavailable { _ = try repository.segments(for: sessionID) }
    }

    /// 欠損の保存・終了・読込はすべて利用不能で失敗します。
    ///
    /// 責務: 欠損Repositoryの全メソッドが空データや成功を返さないことを確認します。
    func testGapOperationsThrowUnavailable() {
        let repository = UnavailableConnectionSessionSegmentationRepository()
        let sessionID = ConnectionSessionID()
        let gap = ConnectionSessionGap(gapOrdinal: 0, precedingSegmentOrdinal: 0, startedAt: Date(timeIntervalSince1970: 1), cause: .linkLost)

        assertUnavailable { try repository.saveGap(gap, for: sessionID) }
        assertUnavailable {
            try repository.finishGap(ordinal: 0, for: sessionID, endedAt: Date(timeIntervalSince1970: 2), followingSegmentOrdinal: nil)
        }
        assertUnavailable { _ = try repository.gaps(for: sessionID) }
    }

    /// 処理が利用不能で失敗することを検証します。
    ///
    /// 責務: 送出されたエラーが `ConnectionSessionRepositoryError.unavailable` であることを確認します。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 検証する処理。
    private func assertUnavailable(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable, file: file, line: line)
        }
    }
}
