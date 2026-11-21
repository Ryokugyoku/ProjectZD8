import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionLocationTrackSyncRepository` の候補・軌跡の読出し・送信済みの記録を仕様から検証します。
final class GRDBConnectionSessionLocationTrackSyncRepositoryTests: XCTestCase {
    /// 値生成の別名です。
    private typealias Values = ConnectionSessionLocationTrackValueFixtures

    // MARK: - uploadCandidates

    /// 何も無いDBでは候補は空です。
    ///
    /// 責務: セッションが無い時に空配列が返ることを確認します。
    func testNoSessionsYieldNoCandidates() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()

        XCTAssertEqual(try fixtures.sync.uploadCandidates(for: "account"), [])
    }

    /// 未終了のセッションは候補になりません。
    ///
    /// 責務: 点があっても終了していないセッションを除くことを確認します。
    func testOpenSessionIsNotCandidate() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        try fixtures.seedSession(samples: 2, events: 1, ended: false)

        XCTAssertEqual(try fixtures.sync.uploadCandidates(for: "account"), [])
    }

    /// 別アカウントのセッションは候補になりません。
    ///
    /// 責務: アカウント識別子が一致しないセッションを除くことを確認します。
    func testOtherAccountSessionIsNotCandidate() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        try fixtures.seedSession(account: "other", samples: 2, events: 1)

        XCTAssertEqual(try fixtures.sync.uploadCandidates(for: "account"), [])
    }

    /// 点も事象も無い終了済みセッションは候補になりません。
    ///
    /// 責務: 軌跡の行が1件も無いセッションを除くことを確認します。
    func testSessionWithoutRowsIsNotCandidate() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        try fixtures.seedSession()

        XCTAssertEqual(try fixtures.sync.uploadCandidates(for: "account"), [])
    }

    /// 復元した記録のあるセッションは候補になりません。
    ///
    /// 責務: origin が restored の同期記録を持つセッションを除くことを確認します。
    func testRestoredSessionIsNotCandidate() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 2, events: 1)
        try fixtures.insertSyncRow(Values.syncRecord(id, origin: .restored, watermark: Values.contiguousWatermark(samples: 2, events: 1)))

        XCTAssertEqual(try fixtures.sync.uploadCandidates(for: "account"), [])
    }

    /// 事象だけのセッションも候補で、水位が実際の件数と最大番号に一致します。
    ///
    /// 責務: 事象だけの終了済みセッションが、同期記録なしの候補として返ることを確認します。
    func testEventsOnlySessionIsCandidateWithWatermark() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(events: 3)

        let candidates = try fixtures.sync.uploadCandidates(for: "account")

        XCTAssertEqual(candidates, [
            ConnectionSessionLocationTrackUploadCandidate(
                sessionID: id, localWatermark: Values.watermark(0, nil, 3, 2), syncRecord: nil
            )
        ])
    }

    /// 位置と事象があるセッションの水位が、件数と最大番号に一致します。
    ///
    /// 責務: サンプル4件・事象2件の終了済みセッションの水位を確認します。
    func testSessionWithBothHasMatchingWatermark() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 4, events: 2)

        let candidates = try fixtures.sync.uploadCandidates(for: "account")

        XCTAssertEqual(candidates.map(\.sessionID), [id])
        XCTAssertEqual(candidates.first?.localWatermark, Values.watermark(4, 3, 2, 1))
        XCTAssertNil(candidates.first?.syncRecord)
    }

    /// 送信済みの記録が付いたセッションは、記録を添えて候補になります。
    ///
    /// 責務: uploaded の同期記録を持つセッションで、記録が全項目そのまま添えられ、水位は現在のローカルの値であることを確認します。
    func testUploadedSessionIsCandidateWithItsRecord() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 5, events: 1)
        let stored = Values.syncRecord(id, digest: Values.digest("b"), watermark: Values.contiguousWatermark(samples: 3, events: 1))
        try fixtures.insertSyncRow(stored)

        let candidates = try fixtures.sync.uploadCandidates(for: "account")

        XCTAssertEqual(candidates, [
            ConnectionSessionLocationTrackUploadCandidate(
                sessionID: id, localWatermark: Values.watermark(5, 4, 1, 0), syncRecord: stored
            )
        ])
    }

    /// 条件を満たすセッションだけが、複数あっても各自の水位で返ります。
    ///
    /// 責務: 2件の対象と除外対象が混在しても、対象だけが自分の水位つきで返ることを確認します。
    func testOnlyEligibleSessionsAreReturnedWithOwnWatermarks() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let first = try fixtures.seedSession(samples: 1)
        let second = try fixtures.seedSession(events: 2)
        try fixtures.seedSession(samples: 3, ended: false)
        try fixtures.seedSession(account: "other", samples: 3)

        let byID = Dictionary(uniqueKeysWithValues: try fixtures.sync.uploadCandidates(for: "account").map { ($0.sessionID, $0) })

        XCTAssertEqual(Set(byID.keys), [first, second])
        XCTAssertEqual(byID[first]?.localWatermark, Values.watermark(1, 0, 0, nil))
        XCTAssertEqual(byID[second]?.localWatermark, Values.watermark(0, nil, 2, 1))
    }

    // MARK: - track(for:)

    /// 行が無ければ、同じセッションIDの空の軌跡が返ります。
    ///
    /// 責務: 行が無いセッションで失敗せず空の軌跡を返すことを確認します。
    func testTrackWithoutRowsIsEmpty() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession()

        let track = try fixtures.sync.track(for: id)

        XCTAssertEqual(track, ConnectionSessionLocationTrack(sessionID: id, samples: [], events: []))
        XCTAssertTrue(track.isEmpty)
    }

    /// 軌跡は sequence・ordinal 昇順で、段階1のRepositoryの読出しと一致します。
    ///
    /// 責務: 位置と事象が追記順に並び、そのセッションの行だけであることを確認します。
    func testTrackReturnsOrderedRowsOfThatSessionOnly() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 3, events: 2)
        try fixtures.seedSession(samples: 5, events: 4)

        let track = try fixtures.sync.track(for: id)

        XCTAssertEqual(track.sessionID, id)
        XCTAssertEqual(track.samples.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(track.events.map(\.ordinal), [0, 1])
        XCTAssertEqual(track.samples, try fixtures.location.locations.samples(for: id))
        XCTAssertEqual(track.events, try fixtures.location.locations.events(for: id))
    }

    // MARK: - syncRecord / markUploaded

    /// 記録が無ければ同期記録は `nil` です。
    ///
    /// 責務: 未記録のセッションで `nil` が返ることを確認します。
    func testSyncRecordIsNilWhenNeverMarked() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 1)

        XCTAssertNil(try fixtures.sync.syncRecord(for: id))
    }

    /// 送信済みの記録を新規に作ると、origin = uploaded で全項目が往復します。
    ///
    /// 責務: ダイジェスト・水位・同期日時が保存され、読み戻せることを確認します。
    func testMarkUploadedCreatesUploadedRecord() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 2, events: 1)
        let mark = Values.contiguousWatermark(samples: 2, events: 1)
        let date = Date(timeIntervalSince1970: 7_000.125)

        try fixtures.sync.markUploaded(sessionID: id, manifestDigest: Values.digest("d"), watermark: mark, at: date)

        XCTAssertEqual(
            try fixtures.sync.syncRecord(for: id),
            ConnectionSessionLocationTrackSyncRecord(sessionID: id, origin: .uploaded, manifestDigest: Values.digest("d"), watermark: mark, syncedAt: date)
        )
    }

    /// 2回目の記録は上書きで、行は1件のままです。
    ///
    /// 責務: 同じセッションへの再記録がダイジェスト・水位・日時を置き換えることを確認します。
    func testMarkUploadedOverwritesExistingRecord() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 3, events: 1)
        try fixtures.sync.markUploaded(
            sessionID: id, manifestDigest: Values.digest("d"), watermark: Values.contiguousWatermark(samples: 2, events: 1),
            at: Date(timeIntervalSince1970: 7_000)
        )
        let newMark = Values.contiguousWatermark(samples: 3, events: 1)
        let newDate = Date(timeIntervalSince1970: 8_000.5)

        try fixtures.sync.markUploaded(sessionID: id, manifestDigest: Values.digest("e"), watermark: newMark, at: newDate)

        XCTAssertEqual(
            try fixtures.sync.syncRecord(for: id),
            ConnectionSessionLocationTrackSyncRecord(
                sessionID: id, origin: .uploaded, manifestDigest: Values.digest("e"), watermark: newMark, syncedAt: newDate
            )
        )
        XCTAssertEqual(try fixtures.syncRowCount(), 1)
    }

    /// 存在しないセッションへの記録は integrityConflict で、何も書かれません。
    ///
    /// 責務: 外部キー違反が `integrityConflict` になり、行が増えないことを確認します。
    func testMarkUploadedForMissingSessionIsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.markUploaded(
                sessionID: ConnectionSessionID(), manifestDigest: Values.digest(),
                watermark: Values.contiguousWatermark(samples: 1, events: 0), at: Date(timeIntervalSince1970: 1)
            )
        }
        XCTAssertEqual(try fixtures.syncRowCount(), 0)
    }

    /// 復元した記録のあるセッションへの記録は integrityConflict で、元の行は不変です。
    ///
    /// 責務: restored の行を uploaded で上書きしないことを確認します。
    func testMarkUploadedOverRestoredRecordIsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 2)
        let restored = Values.syncRecord(id, origin: .restored, digest: Values.digest("f"), watermark: Values.contiguousWatermark(samples: 2, events: 0))
        try fixtures.insertSyncRow(restored)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.markUploaded(
                sessionID: id, manifestDigest: Values.digest("1"),
                watermark: Values.contiguousWatermark(samples: 5, events: 0), at: Date(timeIntervalSince1970: 9_000)
            )
        }
        XCTAssertEqual(try fixtures.sync.syncRecord(for: id), restored)
    }

    /// 長さが64でないダイジェストと空の水位は、制約違反として integrityConflict になります。
    ///
    /// 責務: 不正な引数が保存されず、行が増えないことを確認します。
    func testMarkUploadedRejectsInvalidDigestAndEmptyWatermark() throws {
        let fixtures = try GRDBConnectionSessionLocationTrackSyncFixtures()
        let id = try fixtures.seedSession(samples: 1)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.markUploaded(
                sessionID: id, manifestDigest: String(Values.digest().dropLast()),
                watermark: Values.contiguousWatermark(samples: 1, events: 0), at: Date(timeIntervalSince1970: 1)
            )
        }
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.sync.markUploaded(
                sessionID: id, manifestDigest: Values.digest(), watermark: .empty, at: Date(timeIntervalSince1970: 1)
            )
        }
        XCTAssertEqual(try fixtures.syncRowCount(), 0)
    }
}
