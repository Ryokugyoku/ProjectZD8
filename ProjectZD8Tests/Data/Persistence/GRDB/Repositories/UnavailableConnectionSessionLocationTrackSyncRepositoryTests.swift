import Foundation
import XCTest
@testable import ProjectZD8

/// DB準備不可時の軌跡同期Repositoryが、すべての操作を明示的な利用不能として失敗させることを検証します。
final class UnavailableConnectionSessionLocationTrackSyncRepositoryTests: XCTestCase {
    /// 5つの操作はすべて利用不能で失敗します。
    ///
    /// 責務: 候補・軌跡・同期記録の読出しと、送信済みの記録・復元の書込みが、成功や空の結果を返さないことを確認します。
    func testAllOperationsThrowUnavailable() throws {
        let repository = UnavailableConnectionSessionLocationTrackSyncRepository()
        let sessionID = ConnectionSessionID()
        let track = try ConnectionSessionLocationTrackValueFixtures.track(sessionID, sampleSequences: [0])
        let date = Date(timeIntervalSince1970: 1)

        assertUnavailable { _ = try repository.uploadCandidates(for: "account") }
        assertUnavailable { _ = try repository.track(for: sessionID) }
        assertUnavailable { _ = try repository.syncRecord(for: sessionID) }
        assertUnavailable {
            try repository.markUploaded(
                sessionID: sessionID, manifestDigest: ConnectionSessionLocationTrackValueFixtures.digest(),
                watermark: track.watermark, at: date
            )
        }
        assertUnavailable {
            try repository.replaceWithRestoredTrack(
                VerifiedConnectionSessionLocationTrack(track: track, manifestDigest: ConnectionSessionLocationTrackValueFixtures.digest()), at: date
            )
        }
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
