import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `replaceWithRestoredTrack` の往復・置き換え・衝突・全体性と、セッション削除時の CASCADE を仕様から検証します。
final class GRDBConnectionSessionLocationTrackSyncRepositoryRestoreTests: XCTestCase {
    /// 値生成の別名です。
    private typealias Values = ConnectionSessionLocationTrackValueFixtures
    /// 復元日時です。
    private let restoredAt = Date(timeIntervalSince1970: 6_000.5)

    /// 検証済みの軌跡を作ります。
    ///
    /// 責務: 軌跡とダイジェストを組にします。
    /// - Parameters:
    ///   - track: 軌跡。
    ///   - digest: ダイジェスト。
    /// - Returns: 検証済みの軌跡。
    private func verified(_ track: ConnectionSessionLocationTrack, digest: String = Values.digest("r")) -> VerifiedConnectionSessionLocationTrack {
        VerifiedConnectionSessionLocationTrack(track: track, manifestDigest: digest)
    }

    /// 復元した軌跡を段階1のRepositoryで読むと、番号と全フィールドが一致します。
    ///
    /// 責務: 任意項目の有無が混ざった位置と、全種類の事象が往復で変わらないことを確認します。
    func testRestoredTrackRoundTripsAllFields() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let track = try Values.track(id, sampleSequences: [0, 1, 2, 3], eventOrdinals: Array(0..<ConnectionSessionLocationEventKind.allCases.count))

        try fixtures.sync.replaceWithRestoredTrack(verified(track), at: restoredAt)

        XCTAssertEqual(try fixtures.location.locations.samples(for: id), track.samples)
        XCTAssertEqual(try fixtures.location.locations.events(for: id), track.events)
        XCTAssertEqual(try fixtures.sync.track(for: id), track)
    }

    /// 復元後の同期記録は origin = restored で、ダイジェストと水位は渡した軌跡のものです。
    ///
    /// 責務: 同期記録の全項目を期待値と照合します。
    func testRestoredSyncRecordHasRestoredOriginDigestAndWatermark() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let track = try Values.track(id, sampleSequences: [0, 1, 2], eventOrdinals: [0, 1])

        try fixtures.sync.replaceWithRestoredTrack(verified(track, digest: Values.digest("9")), at: restoredAt)

        XCTAssertEqual(
            try fixtures.sync.syncRecord(for: id),
            ConnectionSessionLocationTrackSyncRecord(
                sessionID: id, origin: .restored, manifestDigest: Values.digest("9"),
                watermark: Values.watermark(3, 2, 2, 1), syncedAt: restoredAt
            )
        )
    }

    /// 歯抜けの番号は、振り直さずに渡された番号どおりに保存されます。
    ///
    /// 責務: sequence と ordinal が連番でない軌跡の番号と水位が保たれることを確認します。
    func testRestoredNumbersArePreservedAsGiven() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let track = try Values.track(id, sampleSequences: [3, 9], eventOrdinals: [2, 4])

        try fixtures.sync.replaceWithRestoredTrack(verified(track), at: restoredAt)

        XCTAssertEqual(try fixtures.location.locations.samples(for: id).map(\.sequence), [3, 9])
        XCTAssertEqual(try fixtures.location.locations.events(for: id).map(\.ordinal), [2, 4])
        XCTAssertEqual(try fixtures.sync.syncRecord(for: id)?.watermark, Values.watermark(2, 9, 2, 4))
    }

    /// 内容の違う軌跡で再度復元すると、古い行は残りません。
    ///
    /// 責務: 1回目より少ない点・事象の2回目で、行数・内容・同期記録がすべて2回目のものになることを確認します。
    func testSecondRestoreReplacesOldRows() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let first = try Values.track(id, sampleSequences: [0, 1, 2, 3], eventOrdinals: [0, 1, 2])
        try fixtures.sync.replaceWithRestoredTrack(verified(first, digest: Values.digest("1")), at: restoredAt)
        let second = try Values.track(id, sampleSequences: [0, 1], eventOrdinals: [0])
        let secondDate = Date(timeIntervalSince1970: 7_000.25)

        try fixtures.sync.replaceWithRestoredTrack(verified(second, digest: Values.digest("2")), at: secondDate)

        XCTAssertEqual(try fixtures.sync.track(for: id), second)
        let counts = try fixtures.location.rowCounts(for: id)
        XCTAssertEqual(counts.samples, 2)
        XCTAssertEqual(counts.events, 1)
        let record = try XCTUnwrap(try fixtures.sync.syncRecord(for: id))
        XCTAssertEqual(record.origin, .restored)
        XCTAssertEqual(record.manifestDigest, Values.digest("2"))
        XCTAssertEqual(record.watermark, second.watermark)
        XCTAssertEqual(record.syncedAt, secondDate)
        XCTAssertEqual(try fixtures.syncRowCount(), 1)
    }

    /// 事象を持たない軌跡で置き換えると、古い事象は残りません。
    ///
    /// 責務: 2回目に事象が0件でも、1回目の事象行が消えることを確認します。
    func testSecondRestoreWithoutEventsRemovesOldEvents() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        try fixtures.sync.replaceWithRestoredTrack(
            verified(try Values.track(id, sampleSequences: [0], eventOrdinals: [0, 1])), at: restoredAt
        )
        let second = try Values.track(id, sampleSequences: [0, 1, 2])

        try fixtures.sync.replaceWithRestoredTrack(verified(second, digest: Values.digest("2")), at: restoredAt)

        XCTAssertEqual(try fixtures.location.rowCounts(for: id).events, 0)
        XCTAssertEqual(try fixtures.sync.track(for: id), second)
    }

    /// 他のセッションの行は、復元で変わりません。
    ///
    /// 責務: 復元が対象セッションの行だけを置き換えることを確認します。
    func testRestoreLeavesOtherSessionsUntouched() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let target = try fixtures.seedSession()
        let other = try fixtures.seedSession(samples: 2, events: 1)
        let otherBefore = try fixtures.sync.track(for: other)

        try fixtures.sync.replaceWithRestoredTrack(verified(try Values.track(target, sampleSequences: [0])), at: restoredAt)

        XCTAssertEqual(try fixtures.sync.track(for: other), otherBefore)
        XCTAssertNil(try fixtures.sync.syncRecord(for: other))
    }

    /// この端末で記録した行があり同期記録が無いセッションは integrityConflict で、行が不変です。
    ///
    /// 責務: 端末の記録を復元で上書きしないことを確認します。
    func testRestoreOverLocallyRecordedRowsIsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 2, events: 1)
        let before = try fixtures.sync.track(for: id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(try Values.track(id, sampleSequences: [0, 1, 2])), at: restoredAt)
        }

        XCTAssertEqual(try fixtures.sync.track(for: id), before)
        XCTAssertNil(try fixtures.sync.syncRecord(for: id))
    }

    /// 送信済み(uploaded)の記録があるセッションも integrityConflict で、行と記録が不変です。
    ///
    /// 責務: この端末が送った軌跡を復元で上書きしないことを確認します。
    func testRestoreOverUploadedSessionIsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 2, events: 1)
        let before = try fixtures.sync.track(for: id)
        try fixtures.sync.markUploaded(sessionID: id, manifestDigest: Values.digest("u"), watermark: before.watermark, at: restoredAt)
        let recordBefore = try fixtures.sync.syncRecord(for: id)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(try Values.track(id, sampleSequences: [0])), at: restoredAt)
        }

        XCTAssertEqual(try fixtures.sync.track(for: id), before)
        XCTAssertEqual(try fixtures.sync.syncRecord(for: id), recordBefore)
    }

    /// 存在しないセッションは integrityConflict で、何も書かれません。
    ///
    /// 責務: 親セッションが無い軌跡の復元が失敗し、軌跡の行も同期記録も作られないことを確認します。
    func testRestoreForMissingSessionIsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let missing = ConnectionSessionID()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(try Values.track(missing, sampleSequences: [0], eventOrdinals: [0])), at: restoredAt)
        }

        XCTAssertEqual(try fixtures.syncRowCount(), 0)
        XCTAssertEqual(try fixtures.location.rowCounts(for: missing).samples, 0)
        XCTAssertEqual(try fixtures.location.rowCounts(for: missing).events, 0)
    }

    /// 同じ sequence が2つある軌跡は integrityConflict で、先に復元した行がそのまま残ります。
    ///
    /// 責務: 途中で制約違反が起きても、削除・挿入・同期記録のどれも反映されないことを確認します。
    func testDuplicateSampleSequenceLeavesPreviousRestoreIntact() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let original = try Values.track(id, sampleSequences: [0, 1, 2], eventOrdinals: [0, 1])
        try fixtures.sync.replaceWithRestoredTrack(verified(original, digest: Values.digest("1")), at: restoredAt)
        let recordBefore = try fixtures.sync.syncRecord(for: id)
        let broken = try Values.track(id, sampleSequences: [0, 0, 1], eventOrdinals: [0])

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(broken, digest: Values.digest("2")), at: Date(timeIntervalSince1970: 9_000))
        }

        XCTAssertEqual(try fixtures.sync.track(for: id), original)
        XCTAssertEqual(try fixtures.sync.syncRecord(for: id), recordBefore)
    }

    /// 同じ ordinal が2つある軌跡も integrityConflict で、先に復元した行がそのまま残ります。
    ///
    /// 責務: サンプルが正しくても事象側の違反で全体が取り消されることを確認します。
    func testDuplicateEventOrdinalLeavesPreviousRestoreIntact() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let original = try Values.track(id, sampleSequences: [0, 1], eventOrdinals: [0, 1, 2])
        try fixtures.sync.replaceWithRestoredTrack(verified(original, digest: Values.digest("1")), at: restoredAt)
        let recordBefore = try fixtures.sync.syncRecord(for: id)
        let broken = try Values.track(id, sampleSequences: [0, 1, 2, 3], eventOrdinals: [0, 1, 1])

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(broken, digest: Values.digest("2")), at: Date(timeIntervalSince1970: 9_000))
        }

        XCTAssertEqual(try fixtures.sync.track(for: id), original)
        XCTAssertEqual(try fixtures.sync.syncRecord(for: id), recordBefore)
    }

    /// 最初の復元で制約違反なら、軌跡の行も同期記録も作られません。
    ///
    /// 責務: 初回でも途中失敗の結果が残らない(何も書かない)ことを確認します。
    func testFirstRestoreWithViolationWritesNothing() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()
        let broken = try Values.track(id, sampleSequences: [0, 1, 1])

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.replaceWithRestoredTrack(verified(broken), at: restoredAt)
        }

        XCTAssertEqual(try fixtures.location.rowCounts(for: id).samples, 0)
        XCTAssertNil(try fixtures.sync.syncRecord(for: id))
    }

    /// セッションを削除すると、軌跡の行と同期記録の行も CASCADE で消えます。
    ///
    /// 責務: 削除したセッションの行が全て消え、別セッションの同期記録は残ることを確認します。
    func testDeletingSessionCascadesToSyncRecordAndRows() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let doomed = try fixtures.seedSession(samples: 2, events: 1)
        let kept = try fixtures.seedSession(samples: 1)
        for id in [doomed, kept] {
            let mark = try fixtures.sync.track(for: id).watermark
            try fixtures.sync.markUploaded(sessionID: id, manifestDigest: Values.digest(), watermark: mark, at: restoredAt)
        }

        try fixtures.queue.write { database in
            try database.execute(sql: "DELETE FROM connection_sessions WHERE id = ?", arguments: [doomed.rawValue.uuidString.lowercased()])
        }

        XCTAssertNil(try fixtures.sync.syncRecord(for: doomed))
        XCTAssertNotNil(try fixtures.sync.syncRecord(for: kept))
        XCTAssertEqual(try fixtures.syncRowCount(), 1)
        XCTAssertEqual(try fixtures.location.rowCounts(for: doomed).samples, 0)
        XCTAssertEqual(try fixtures.location.rowCounts(for: doomed).events, 0)
    }
}
