import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionLocationRepository` の位置・事象の追記と読出しを仕様から検証します。
final class GRDBConnectionSessionLocationRepositoryTests: XCTestCase {
    // MARK: - appendSample / samples(for:)

    /// 全項目に値を持つ位置が、全フィールドを保って往復します。
    ///
    /// 責務: 緯度経度・標高・精度・速度・進行方向・観測時刻・単調時刻の保存と復元の一致を確認します。
    func testSampleRoundTripsAllFields() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        let fix = try GRDBConnectionSessionLocationFixtures.fix()

        try fixtures.locations.appendSample(fix, for: sessionID)

        let samples = try fixtures.locations.samples(for: sessionID)
        XCTAssertEqual(samples, [ConnectionSessionLocationSample(sequence: 0, fix: fix)])
    }

    /// 任意項目が `nil` の位置も `nil` のまま往復します。
    ///
    /// 責務: 標高・垂直精度・速度・進行方向が `nil`、水平精度と単調時刻が 0 の位置の一致を確認します。
    func testSampleWithoutOptionalFieldsRoundTrips() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        let fix = try GRDBConnectionSessionLocationFixtures.fixWithoutOptionals()

        try fixtures.locations.appendSample(fix, for: sessionID)

        let loaded = try XCTUnwrap(try fixtures.locations.samples(for: sessionID).first)
        XCTAssertEqual(loaded.fix, fix)
        XCTAssertNil(loaded.fix.altitudeMeters)
        XCTAssertNil(loaded.fix.verticalAccuracyMeters)
        XCTAssertNil(loaded.fix.speedMetersPerSecond)
        XCTAssertNil(loaded.fix.courseDegrees)
    }

    /// sequence は 0 から 1 ずつ増え、sequence 昇順で返ります。
    ///
    /// 責務: 追記順に 0, 1, 2 が採番され、読出し順と内容が追記順に一致することを確認します。
    func testSequencesStartAtZeroAndIncrementByOne() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        let fixes = try (0..<3).map {
            try GRDBConnectionSessionLocationFixtures.fix(latitude: 10 + Double($0), observedAt: Date(timeIntervalSince1970: 3_000 + Double($0)))
        }

        for fix in fixes {
            try fixtures.locations.appendSample(fix, for: sessionID)
        }

        let samples = try fixtures.locations.samples(for: sessionID)
        XCTAssertEqual(samples.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(samples.map(\.fix), fixes)
    }

    /// 別セッションの位置は混ざらず、sequence はセッションごとに 0 から始まります。
    ///
    /// 責務: 2セッションへ交互に追記しても、各セッションが自分の位置だけを独立した連番で返すことを確認します。
    func testSamplesAreScopedToSessionWithIndependentSequences() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let first = try fixtures.seedSession()
        let second = try fixtures.seedSession()
        let firstFix = try GRDBConnectionSessionLocationFixtures.fix(latitude: 1)
        let secondFix = try GRDBConnectionSessionLocationFixtures.fix(latitude: 2)

        try fixtures.locations.appendSample(firstFix, for: first)
        try fixtures.locations.appendSample(secondFix, for: second)
        try fixtures.locations.appendSample(firstFix, for: first)

        XCTAssertEqual(try fixtures.locations.samples(for: first).map(\.sequence), [0, 1])
        XCTAssertEqual(try fixtures.locations.samples(for: first).map(\.fix), [firstFix, firstFix])
        XCTAssertEqual(try fixtures.locations.samples(for: second), [ConnectionSessionLocationSample(sequence: 0, fix: secondFix)])
    }

    /// Repository を作り直しても、続きの sequence が採番されます。
    ///
    /// 責務: 続行で復帰したセッションを想定し、同じDBの新しいインスタンスからの追記が 1, 2 になることを確認します。
    func testSequenceContinuesAfterRepositoryIsRecreated() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        try fixtures.locations.appendSample(try GRDBConnectionSessionLocationFixtures.fix(), for: sessionID)

        let recreated = try fixtures.makeRecreatedRepository()
        try recreated.appendSample(try GRDBConnectionSessionLocationFixtures.fix(latitude: 40), for: sessionID)
        try recreated.appendSample(try GRDBConnectionSessionLocationFixtures.fix(latitude: 41), for: sessionID)

        XCTAssertEqual(try recreated.samples(for: sessionID).map(\.sequence), [0, 1, 2])
        XCTAssertEqual(try fixtures.locations.samples(for: sessionID).map(\.fix.latitude), [35.5, 40, 41])
    }

    /// 位置が無いセッションの `samples(for:)` は空配列です。
    ///
    /// 責務: 位置が無い保存済みセッションと、未知のセッションIDの両方で空配列になることを確認します。
    func testSamplesWithoutRowsAreEmpty() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()

        XCTAssertEqual(try fixtures.locations.samples(for: sessionID), [])
        XCTAssertEqual(try fixtures.locations.samples(for: ConnectionSessionID()), [])
    }

    /// 存在しないセッションへの `appendSample` は `integrityConflict` で、行を作りません。
    ///
    /// 責務: セッション不在の失敗の種類と、失敗後に行が増えないことを確認します。
    func testAppendSampleToMissingSessionThrowsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let missing = ConnectionSessionID()
        let fix = try GRDBConnectionSessionLocationFixtures.fix()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.locations.appendSample(fix, for: missing)
        }

        XCTAssertEqual(try fixtures.locations.samples(for: missing), [])
        XCTAssertEqual(try fixtures.rowCounts(for: missing).samples, 0)
    }

    // MARK: - appendEvent / events(for:)

    /// 事象は ordinal 昇順(0 始まり)で、kind と時刻を保って返ります。
    ///
    /// 責務: 追記順に 0, 1 が採番され、kind と occurredAt が往復することを確認します。
    func testEventsRoundTripInOrdinalOrder() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        let firstTime = Date(timeIntervalSince1970: 4_000.5)
        let secondTime = Date(timeIntervalSince1970: 4_010.25)

        try fixtures.locations.appendEvent(.recording, occurredAt: firstTime, for: sessionID)
        try fixtures.locations.appendEvent(.locationUnavailable, occurredAt: secondTime, for: sessionID)

        XCTAssertEqual(
            try fixtures.locations.events(for: sessionID),
            [
                ConnectionSessionLocationEvent(ordinal: 0, occurredAt: firstTime, kind: .recording),
                ConnectionSessionLocationEvent(ordinal: 1, occurredAt: secondTime, kind: .locationUnavailable)
            ]
        )
    }

    /// 9種類の kind がすべて保存・復元できます。
    ///
    /// 責務: `ConnectionSessionLocationEventKind.allCases` が9件であることと、全 kind の往復一致を確認します。
    func testAllEventKindsRoundTrip() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()
        let kinds = ConnectionSessionLocationEventKind.allCases
        XCTAssertEqual(kinds.count, 9)

        for kind in kinds {
            try fixtures.locations.appendEvent(kind, occurredAt: Date(timeIntervalSince1970: 5_000), for: sessionID)
        }

        let events = try fixtures.locations.events(for: sessionID)
        XCTAssertEqual(events.map(\.kind), kinds)
        XCTAssertEqual(events.map(\.ordinal), Array(0..<9))
    }

    /// 事象はセッションごとに独立して 0 から採番され、Repository を作り直しても続きが採番されます。
    ///
    /// 責務: 別セッションの事象が混ざらないことと、再作成後の ordinal の継続を確認します。
    func testEventsAreScopedToSessionAndOrdinalContinuesAfterRecreation() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let first = try fixtures.seedSession()
        let second = try fixtures.seedSession()
        let time = Date(timeIntervalSince1970: 6_000)
        try fixtures.locations.appendEvent(.recording, occurredAt: time, for: first)
        try fixtures.locations.appendEvent(.authorizationDenied, occurredAt: time, for: second)

        try fixtures.makeRecreatedRepository().appendEvent(.locationUnavailable, occurredAt: time, for: first)

        let firstEvents = try fixtures.locations.events(for: first)
        XCTAssertEqual(firstEvents.map(\.ordinal), [0, 1])
        XCTAssertEqual(firstEvents.map(\.kind), [.recording, .locationUnavailable])
        XCTAssertEqual(try fixtures.locations.events(for: second).map(\.ordinal), [0])
        XCTAssertEqual(try fixtures.locations.events(for: second).map(\.kind), [.authorizationDenied])
    }

    /// 事象が無いセッションの `events(for:)` は空配列です。
    ///
    /// 責務: 事象が無い保存済みセッションと未知のセッションIDで空配列になることを確認します。
    func testEventsWithoutRowsAreEmpty() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let sessionID = try fixtures.seedSession()

        XCTAssertEqual(try fixtures.locations.events(for: sessionID), [])
        XCTAssertEqual(try fixtures.locations.events(for: ConnectionSessionID()), [])
    }

    /// 存在しないセッションへの `appendEvent` は `integrityConflict` で、行を作りません。
    ///
    /// 責務: セッション不在の失敗の種類と、失敗後に行が増えないことを確認します。
    func testAppendEventToMissingSessionThrowsIntegrityConflict() throws {
        let fixtures = try GRDBConnectionSessionLocationFixtures()
        let missing = ConnectionSessionID()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.locations.appendEvent(.recording, occurredAt: Date(timeIntervalSince1970: 7_000), for: missing)
        }

        XCTAssertEqual(try fixtures.locations.events(for: missing), [])
        XCTAssertEqual(try fixtures.rowCounts(for: missing).events, 0)
    }
}
