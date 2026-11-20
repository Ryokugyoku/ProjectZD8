import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// セッション削除で位置・事象の行が消えること、Rawログの端末退避と転送の復元では残ることを検証します。
final class GRDBConnectionSessionLocationRepositoryRetentionTests: XCTestCase {
    /// 位置2点と事象1件を追記します。
    ///
    /// 責務: 保持・削除の検証対象となる行を1セッションへ用意します。
    /// - Parameters:
    ///   - fixtures: 検証用の組立て。
    ///   - sessionID: 追記先のセッションID。
    /// - Throws: 追記の失敗。
    private func appendRows(_ fixtures: GRDBConnectionSessionLocationFixtures, to sessionID: ConnectionSessionID) throws {
        try fixtures.locations.appendSample(try GRDBConnectionSessionLocationFixtures.fix(), for: sessionID)
        try fixtures.locations.appendSample(try GRDBConnectionSessionLocationFixtures.fix(latitude: 36), for: sessionID)
        try fixtures.locations.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 8_000), for: sessionID)
    }

    /// 位置2点と事象1件が残っていることを確かめます。
    ///
    /// 責務: 行数とRepository経由の読出しの両方で、追記した内容が保たれていることを検証します。
    /// - Parameters:
    ///   - fixtures: 検証用の組立て。
    ///   - sessionID: 検証するセッションID。
    private func assertRowsRemain(
        _ fixtures: GRDBConnectionSessionLocationFixtures,
        for sessionID: ConnectionSessionID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let counts = try fixtures.rowCounts(for: sessionID)
        XCTAssertEqual(counts.samples, 2, file: file, line: line)
        XCTAssertEqual(counts.events, 1, file: file, line: line)
        XCTAssertEqual(try fixtures.locations.samples(for: sessionID).map(\.sequence), [0, 1], file: file, line: line)
        XCTAssertEqual(try fixtures.locations.events(for: sessionID).map(\.kind), [.recording], file: file, line: line)
    }

    /// `deleteSession` で、そのセッションの位置と事象が消え、他セッションの行は残ります。
    ///
    /// 責務: 1件の削除が対象セッションの2表の行だけを消すことを確認します。
    func testDeleteSessionRemovesLocationRowsOnlyForThatSession() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let target = try fixtures.seedSession()
        let other = try fixtures.seedSession()
        try appendRows(fixtures, to: target)
        try appendRows(fixtures, to: other)

        try fixtures.sessions.deleteSession(target, for: "account")

        let removed = try fixtures.rowCounts(for: target)
        XCTAssertEqual(removed.samples, 0)
        XCTAssertEqual(removed.events, 0)
        try assertRowsRemain(fixtures, for: other)
    }

    /// `deleteSessions` で、そのアカウントの全セッションの位置と事象が消え、他アカウントの行は残ります。
    ///
    /// 責務: アカウント単位の削除が2表の行へ及び、他アカウントへ及ばないことを確認します。
    func testDeleteSessionsRemovesLocationRowsForAccountOnly() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let firstOwned = try fixtures.seedSession(account: "deleted")
        let secondOwned = try fixtures.seedSession(account: "deleted")
        let kept = try fixtures.seedSession(account: "kept")
        for id in [firstOwned, secondOwned, kept] {
            try appendRows(fixtures, to: id)
        }

        try fixtures.sessions.deleteSessions(for: "deleted")

        for id in [firstOwned, secondOwned] {
            let counts = try fixtures.rowCounts(for: id)
            XCTAssertEqual(counts.samples, 0)
            XCTAssertEqual(counts.events, 0)
        }
        try assertRowsRemain(fixtures, for: kept)
    }

    /// Raw ログの端末退避(`removeLocalEntries`)では、位置と事象の行が残ります。
    ///
    /// 責務: Raw行だけを消す操作が位置・事象に影響しないことを確認します。
    func testRemoveLocalEntriesKeepsLocationRows() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let session = try fixtures.base.seedEndedSession(rawCount: 2)
        try appendRows(fixtures, to: session.id)

        try fixtures.sessions.removeLocalEntries(for: session.id)

        XCTAssertEqual(try fixtures.sessions.entries(for: session.id), [])
        try assertRowsRemain(fixtures, for: session.id)
    }

    /// 転送の復元(`restoreVerifiedTransfer`)では、位置と事象の行が残ります。
    ///
    /// 責務: Rawログを置き換える復元が位置・事象に影響しないことを確認します。
    func testRestoreVerifiedTransferKeepsLocationRows() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let session = try fixtures.base.seedEndedSession(rawCount: 2)
        try appendRows(fixtures, to: session.id)
        let entries = [
            ConnectionSessionRawLogEntry(
                sequence: 0, observedAt: Date(timeIntervalSince1970: 1_000), batchElapsedNanoseconds: 5,
                service: 0x01, pid: 0x0C, payload: [0xAA]
            )
        ]
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: entries),
            manifestDigest: "digest"
        )

        try fixtures.sessions.restoreVerifiedTransfer(transfer)

        XCTAssertEqual(try fixtures.sessions.entries(for: session.id), entries)
        try assertRowsRemain(fixtures, for: session.id)
    }
}
