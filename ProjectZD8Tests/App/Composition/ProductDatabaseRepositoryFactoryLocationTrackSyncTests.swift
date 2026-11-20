import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品DBを開けない時に軌跡同期Repositoryが利用不能な実装になり、開ける時はGRDB実装で動くことを検証します。
@MainActor
final class ProductDatabaseRepositoryFactoryLocationTrackSyncTests: XCTestCase {
    /// DBを開けなかった失敗を表すテスト用エラーです。
    private struct OpenFailure: Error, Equatable {}

    /// 製品DBを開けなければ、利用不能な実装が返り、診断が元のエラーで1件残ります。
    ///
    /// 責務: 返ったRepositoryの操作が `unavailable` で失敗し、開けなかった元のエラーが診断へ渡ることを確認します。
    func testUnopenableDatabaseReturnsUnavailableRepositoryWithDiagnostics() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeConnectionSessionLocationTrackSyncRepository(database: database)

        XCTAssertTrue(repository is UnavailableConnectionSessionLocationTrackSyncRepository)
        XCTAssertEqual(spy.entries.count, 1)
        XCTAssertEqual(spy.entries.first?.error as? OpenFailure, OpenFailure())
        XCTAssertThrowsError(try repository.uploadCandidates(for: "account")) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable)
        }
        XCTAssertThrowsError(try repository.track(for: ConnectionSessionID())) {
            XCTAssertEqual($0 as? ConnectionSessionRepositoryError, .unavailable)
        }
    }

    /// 製品DBを開ければ、GRDB実装が返り、診断は残らず、同期記録を保存して読めます。
    ///
    /// 責務: 成功時に利用不能へ差し替えないことと、返ったRepositoryの送信済みの記録の往復を確認します。
    func testOpenableDatabaseReturnsWorkingGRDBRepositoryWithoutDiagnostics() throws {
        let queue = try DatabaseQueue()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { queue })
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeConnectionSessionLocationTrackSyncRepository(database: database)
        let sessionID = ConnectionSessionID()
        try GRDBConnectionSessionRepository(databaseQueue: queue)
            .save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100)))
        let mark = ConnectionSessionLocationTrackValueFixtures.contiguousWatermark(samples: 2, events: 1)
        let digest = ConnectionSessionLocationTrackValueFixtures.digest()
        let date = Date(timeIntervalSince1970: 5_000.5)

        try repository.markUploaded(sessionID: sessionID, manifestDigest: digest, watermark: mark, at: date)

        XCTAssertTrue(repository is GRDBConnectionSessionLocationTrackSyncRepository)
        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertEqual(
            try repository.syncRecord(for: sessionID),
            ConnectionSessionLocationTrackSyncRecord(sessionID: sessionID, origin: .uploaded, manifestDigest: digest, watermark: mark, syncedAt: date)
        )
    }
}
