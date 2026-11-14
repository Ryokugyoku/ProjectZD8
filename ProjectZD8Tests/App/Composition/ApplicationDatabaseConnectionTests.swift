import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品DBを起動時1回だけ開く共有接続の回数・同一性・失敗保持・Repository共有を検証します。
final class ApplicationDatabaseConnectionTests: XCTestCase {
    /// DB Queueを開けない場合に投げるテスト用エラーです。
    private struct OpenFailure: Error, Equatable {
        /// 失敗を区別する識別値です。
        let code: Int
    }

    /// 開く処理は生成時にちょうど1回だけ呼ばれます。
    ///
    /// 責務: 生成直後と `databaseQueue()` 複数回呼出し後で、開く処理の呼出し回数が1回のままであることを確認します。
    func testOpenerIsCalledExactlyOnceAtInitialization() throws {
        var openCount = 0

        let connection = ApplicationDatabaseConnection(openDatabaseQueue: {
            openCount += 1
            return try DatabaseQueue()
        })
        XCTAssertEqual(openCount, 1)
        for _ in 0..<5 {
            _ = try connection.databaseQueue()
        }

        XCTAssertEqual(openCount, 1)
    }

    /// `databaseQueue()` は常に同一インスタンスを返します。
    ///
    /// 責務: 複数回の取得結果が `===` で一致し、開き直されないことを確認します。
    func testDatabaseQueueReturnsSameInstanceEveryTime() throws {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { try DatabaseQueue() })

        let first = try connection.databaseQueue()
        let second = try connection.databaseQueue()
        let third = try connection.databaseQueue()

        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
    }

    /// 渡したQueueそのものが返されます。
    ///
    /// 責務: 注入した処理が返したQueueと `databaseQueue()` の結果が同一であることを確認します。
    func testDatabaseQueueReturnsQueueProducedByOpener() throws {
        let expected = try DatabaseQueue()

        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { expected })

        XCTAssertTrue(try connection.databaseQueue() === expected)
    }

    /// 開く処理の失敗は毎回同じ失敗として投げられ、開き直されません。
    ///
    /// 責務: 失敗を保持して再送出し、追加の開く処理が走らないことを確認します。
    func testDatabaseQueueRethrowsOpenFailureWithoutReopening() {
        var openCount = 0
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: {
            openCount += 1
            throw OpenFailure(code: 7)
        })

        for _ in 0..<3 {
            XCTAssertThrowsError(try connection.databaseQueue()) { error in
                XCTAssertEqual(error as? OpenFailure, OpenFailure(code: 7))
            }
        }

        XCTAssertEqual(openCount, 1)
    }

    /// 同じ接続から作った複数のRepositoryが同じDBを見ます。
    ///
    /// 責務: 一方のRepositoryで書いたセッションとセグメントを、別のRepositoryインスタンスから読めることを確認します。
    func testRepositoriesBuiltFromOneConnectionShareTheSameDatabase() throws {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { try DatabaseQueue() })
        let writerSessions = try GRDBConnectionSessionRepository(databaseQueue: connection.databaseQueue())
        let writerSegments = try GRDBConnectionSessionSegmentRepository(databaseQueue: connection.databaseQueue())
        let session = ConnectionSession(accountIdentifier: "shared", startedAt: Date(timeIntervalSince1970: 100))
        let segment = ConnectionSessionSegment(
            segmentOrdinal: 0,
            startReason: .initial,
            acquisitionMode: .pidPolling,
            startedAt: Date(timeIntervalSince1970: 101),
            monotonicAnchorNanoseconds: 5,
            firstSequence: 0
        )

        try writerSessions.save(session)
        try writerSegments.beginSegment(segment, for: session.id)

        let readerSessions = try GRDBConnectionSessionRepository(databaseQueue: connection.databaseQueue())
        let readerSegments = try GRDBConnectionSessionSegmentRepository(databaseQueue: connection.databaseQueue())
        XCTAssertEqual(try readerSessions.sessions(for: "shared"), [session])
        XCTAssertEqual(try readerSegments.segments(for: session.id), [segment])
    }

    /// 開けない接続を渡すと接続session保存先は両方とも利用不能実装になります。
    ///
    /// 責務: 失敗した共有接続から `makeProduction` を組み立てたとき成功扱いにならないことを確認します。
    func testMakeProductionWithFailedConnectionUsesUnavailableRepositories() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { throw OpenFailure(code: 1) })

        let dependencies = ConnectionSessionStorageDependencies.makeProduction(
            openDatabaseQueue: connection.databaseQueue
        )

        XCTAssertTrue(dependencies.sessions is UnavailableConnectionSessionRepository)
        XCTAssertTrue(dependencies.acquisition is UnavailableConnectionSessionRepository)
    }

    /// 開ける接続を渡すと接続session保存先はGRDB実装になります。
    ///
    /// 責務: 正常な共有接続では利用不能実装へ落ちないこと(上の失敗系の対照)を確認します。
    func testMakeProductionWithOpenConnectionUsesGRDBRepositories() {
        let connection = ApplicationDatabaseConnection(openDatabaseQueue: { try DatabaseQueue() })

        let dependencies = ConnectionSessionStorageDependencies.makeProduction(
            openDatabaseQueue: connection.databaseQueue
        )

        XCTAssertTrue(dependencies.sessions is GRDBConnectionSessionRepository)
        XCTAssertTrue(dependencies.acquisition is GRDBConnectionSessionAcquisitionRepository)
    }
}
