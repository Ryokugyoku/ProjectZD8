import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// Raw応答を1件ずつ採番して追記する `appendNextSequence` が、未終了セッションだけへ書き、不明・終了済みを拒否することを検証します。
///
/// 削除した `GRDBConnectionSessionRepository.append` のテストが確かめていた拒否の観点を、残っている採番追記に対して確かめます。
@MainActor
final class GRDBConnectionSessionRawLogAppenderTests: XCTestCase {
    /// 未終了セッションへ追記すると、0から順に採番し、親の件数・バイト数を更新します。
    ///
    /// 責務: 採番と親集計の更新を確認します。
    func testAppendNextSequenceNumbersFromZeroAndUpdatesParentSummary() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = ConnectionSession(accountIdentifier: "account")
        try fixtures.repository.save(session)

        let first = try append(GRDBConnectionSessionRepositoryFixtures.observation(payload: [0x01, 0x02]), to: session.id, in: fixtures)
        let second = try append(GRDBConnectionSessionRepositoryFixtures.observation(payload: [0x03]), to: session.id, in: fixtures)

        XCTAssertEqual([first.sequence, second.sequence], [0, 1])
        XCTAssertEqual(try fixtures.repository.entries(for: session.id).map(\.payload), [[0x01, 0x02], [0x03]])
        let record = try fixtures.storedRecord(session.id)
        XCTAssertEqual(record.rawRecordCount, 2)
        XCTAssertEqual(record.rawByteCount, 3)
    }

    /// 存在しないセッションへの追記は `invalidState` で、Raw行を作りません。
    ///
    /// 責務: 不明セッションへの追記を拒否することを確認します。
    func testAppendNextSequenceToUnknownSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let unknown = ConnectionSessionID()

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            _ = try self.append(GRDBConnectionSessionRepositoryFixtures.observation(), to: unknown, in: fixtures)
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: unknown), 0)
    }

    /// 終了済みセッションへの追記は `invalidState` で、件数が増えません。
    ///
    /// 責務: 終了後のRaw追記を拒否することを確認します。
    func testAppendNextSequenceToEndedSessionThrowsInvalidState() throws {
        let fixtures = try GRDBConnectionSessionRepositoryFixtures()
        let session = try fixtures.seedEndedSession(rawCount: 1)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            _ = try self.append(GRDBConnectionSessionRepositoryFixtures.observation(), to: session.id, in: fixtures)
        }
        XCTAssertEqual(try fixtures.repository.entryCount(for: session.id), 1)
    }

    /// 検証対象の採番追記を1回の書き込みトランザクションで呼びます。
    ///
    /// 責務: テスト用DBの書き込み境界で `appendNextSequence` を実行します。
    /// - Parameters:
    ///   - observation: 追記する未デコード応答。
    ///   - sessionID: 追記先のセッションID。
    ///   - fixtures: 書き込み先のDBを持つ前準備。
    /// - Returns: 採番済みのRaw entry。
    private func append(
        _ observation: OBDRawResponseObservation,
        to sessionID: ConnectionSessionID,
        in fixtures: GRDBConnectionSessionRepositoryFixtures
    ) throws -> ConnectionSessionRawLogEntry {
        try fixtures.queue.write { database in
            try GRDBConnectionSessionRawLogAppender().appendNextSequence(observation, to: sessionID, in: database)
        }
    }
}
