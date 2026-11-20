import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品DBを開けない時に位置Repositoryが利用不能な実装になり、開ける時はGRDB実装で追記と読出しができることを検証します。
@MainActor
final class ProductDatabaseRepositoryFactoryLocationTests: XCTestCase {
    /// DBを開けなかった失敗を表すテスト用エラーです。
    private struct OpenFailure: Error, Equatable {}

    /// 製品DBを開けなければ、利用不能な位置Repositoryが返り、診断が元のエラーで1件残ります。
    ///
    /// 責務: 返ったRepositoryの4操作がすべて `unavailable` で失敗し、開けなかった元のエラーが診断へ渡ることを確認します。
    func testUnopenableDatabaseReturnsUnavailableRepositoryWithDiagnostics() throws {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure() })

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeConnectionSessionLocationRepository(database: database)

        XCTAssertTrue(repository is UnavailableConnectionSessionLocationRepository)
        XCTAssertEqual(spy.entries.count, 1)
        XCTAssertEqual(spy.entries.first?.error as? OpenFailure, OpenFailure())
        let sessionID = ConnectionSessionID()
        let fix = try GRDBConnectionSessionLocationFixtures.fix()
        assertUnavailable { try repository.appendSample(fix, for: sessionID) }
        assertUnavailable { _ = try repository.samples(for: sessionID) }
        assertUnavailable { try repository.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 1), for: sessionID) }
        assertUnavailable { _ = try repository.events(for: sessionID) }
    }

    /// 製品DBを開ければ、GRDB実装が返り、診断は残らず、追記と読出しができます。
    ///
    /// 責務: 成功時に利用不能へ差し替えないことと、返ったRepositoryの位置・事象の往復を確認します。
    func testOpenableDatabaseReturnsWorkingGRDBRepositoryWithoutDiagnostics() throws {
        let queue = try DatabaseQueue()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { queue })
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeConnectionSessionLocationRepository(database: database)
        let sessionID = ConnectionSessionID()
        try GRDBConnectionSessionRepository(databaseQueue: queue)
            .save(ConnectionSession(id: sessionID, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100)))
        let fix = try GRDBConnectionSessionLocationFixtures.fix()

        try repository.appendSample(fix, for: sessionID)
        try repository.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 200), for: sessionID)

        XCTAssertTrue(repository is GRDBConnectionSessionLocationRepository)
        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertEqual(try repository.samples(for: sessionID), [ConnectionSessionLocationSample(sequence: 0, fix: fix)])
        XCTAssertEqual(try repository.events(for: sessionID).map(\.kind), [.recording])
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
