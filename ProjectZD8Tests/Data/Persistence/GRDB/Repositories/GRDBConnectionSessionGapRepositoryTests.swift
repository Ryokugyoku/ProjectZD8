import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionGapRepository` の保存・終了・読込・エラー分類を仕様から検証します。
final class GRDBConnectionSessionGapRepositoryTests: XCTestCase {
    /// セグメント0・1を持つ検証用の組立てを返します。
    ///
    /// 責務: 欠損の前後参照に使う2件の未終了セグメントを保存した組立てを用意します。
    private func makeFixtures() throws -> GRDBSegmentationRepositoryFixtures {
        let fixtures = try GRDBSegmentationRepositoryFixtures()
        for ordinal in 0...1 {
            try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: ordinal), for: fixtures.sessionID)
        }
        return fixtures
    }

    // MARK: - saveGap / gaps(for:)

    /// 未終了・終了済みの空白が等しく読めます。
    ///
    /// 責務: 未終了の空白と、終了時刻・直後セグメント付きの空白の往復一致を確認します。
    func testSaveGapRoundTripsOpenAndClosedGaps() throws {
        let fixtures = try makeFixtures()
        let open = GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, startedAt: Date(timeIntervalSince1970: 2_000.5))
        let closed = GRDBSegmentationRepositoryFixtures.gap(
            ordinal: 1, preceding: 0, following: 1,
            startedAt: Date(timeIntervalSince1970: 2_001), endedAt: Date(timeIntervalSince1970: 2_002.25), cause: .adapterBufferFull
        )

        try fixtures.gaps.saveGap(open, for: fixtures.sessionID)
        try fixtures.gaps.saveGap(closed, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), [open, closed])
    }

    /// 時刻はマイクロ秒精度へ最近傍丸めで保存されます。
    ///
    /// 責務: 開始・終了時刻の端数が最近傍のマイクロ秒になることを確認します。
    func testGapTimesAreRoundedToNearestMicrosecond() throws {
        let fixtures = try makeFixtures()
        let gap = GRDBSegmentationRepositoryFixtures.gap(
            startedAt: Date(timeIntervalSince1970: 100.0000004), endedAt: Date(timeIntervalSince1970: 100.0000016)
        )

        try fixtures.gaps.saveGap(gap, for: fixtures.sessionID)

        let loaded = try XCTUnwrap(try fixtures.gaps.gaps(for: fixtures.sessionID).first)
        XCTAssertEqual(loaded.startedAt, Date(timeIntervalSince1970: 100.0))
        XCTAssertEqual(loaded.endedAt, Date(timeIntervalSince1970: 100.000002))
    }

    /// 空白は `gapOrdinal` 昇順で返り、他セッションの空白は混ざりません。
    ///
    /// 責務: 保存順が逆でも昇順になることと、セッション単位の絞り込みを確認します。
    func testGapsAreOrderedByOrdinalAndScopedToSession() throws {
        let fixtures = try makeFixtures()
        let other = try fixtures.makeOtherSession()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: other)
        for ordinal in [2, 0, 1] {
            try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: ordinal), for: fixtures.sessionID)
        }
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 9), for: other)

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID).map(\.gapOrdinal), [0, 1, 2])
        XCTAssertEqual(try fixtures.gaps.gaps(for: other).map(\.gapOrdinal), [9])
        XCTAssertEqual(try fixtures.gaps.gaps(for: ConnectionSessionID()), [])
    }

    /// 5つの原因がすべて往復します。
    ///
    /// 責務: 原因ごとの保存と読込の一致を確認します。
    func testAllCausesRoundTrip() throws {
        let fixtures = try makeFixtures()
        let causes: [ConnectionSessionGapCause] = [.linkLost, .processTerminated, .responseStall, .adapterBufferFull, .bufferOverflow]
        let expected = causes.enumerated().map { GRDBSegmentationRepositoryFixtures.gap(ordinal: $0.offset, cause: $0.element) }

        for gap in expected {
            try fixtures.gaps.saveGap(gap, for: fixtures.sessionID)
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), expected)
    }

    // MARK: - finishGap

    /// 終了すると終了時刻と直後セグメント番号が反映されます。
    ///
    /// 責務: 直後ありの終了と、直後 `nil` の終了の両方を確認します。
    func testFinishGapAppliesEndTimeAndFollowingSegment() throws {
        let fixtures = try makeFixtures()
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 0), for: fixtures.sessionID)
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 1, cause: .processTerminated), for: fixtures.sessionID)

        try fixtures.gaps.finishGap(
            ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_500), followingSegmentOrdinal: 1
        )
        try fixtures.gaps.finishGap(
            ordinal: 1, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_600), followingSegmentOrdinal: nil
        )

        let loaded = try fixtures.gaps.gaps(for: fixtures.sessionID)
        XCTAssertEqual(loaded[0].endedAt, Date(timeIntervalSince1970: 2_500))
        XCTAssertEqual(loaded[0].followingSegmentOrdinal, 1)
        XCTAssertEqual(loaded[1].endedAt, Date(timeIntervalSince1970: 2_600))
        XCTAssertNil(loaded[1].followingSegmentOrdinal)
        XCTAssertEqual(loaded[1].cause, .processTerminated)
    }

    // MARK: - invalidState

    /// 存在しない空白の `finishGap` は `invalidState` です。
    ///
    /// 責務: 番号違い・別セッションの空白への終了が拒否され、行が変わらないことを確認します。
    func testFinishMissingGapIsInvalidState() throws {
        let fixtures = try makeFixtures()
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 0), for: fixtures.sessionID)
        let before = try fixtures.gaps.gaps(for: fixtures.sessionID)

        for (ordinal, session) in [(3, fixtures.sessionID), (0, ConnectionSessionID())] {
            assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
                try fixtures.gaps.finishGap(
                    ordinal: ordinal, for: session, endedAt: Date(timeIntervalSince1970: 3_000), followingSegmentOrdinal: nil
                )
            }
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), before)
    }

    /// 終了済み空白の `finishGap` は `invalidState` で、先の終了情報が保たれます。
    ///
    /// 責務: 保存時から終了済みの空白と、`finishGap` で終了した空白の両方への再終了が拒否されることを確認します。
    func testFinishAlreadyFinishedGapIsInvalidState() throws {
        let fixtures = try makeFixtures()
        let closed = GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, endedAt: Date(timeIntervalSince1970: 2_100))
        try fixtures.gaps.saveGap(closed, for: fixtures.sessionID)
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 1), for: fixtures.sessionID)
        try fixtures.gaps.finishGap(
            ordinal: 1, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_200), followingSegmentOrdinal: 1
        )
        let before = try fixtures.gaps.gaps(for: fixtures.sessionID)

        for ordinal in [0, 1] {
            assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
                try fixtures.gaps.finishGap(
                    ordinal: ordinal, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 9_000), followingSegmentOrdinal: nil
                )
            }
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), before)
    }

    // MARK: - integrityConflict

    /// 番号重複は `integrityConflict` で、既存行は変わりません。
    ///
    /// 責務: 同一セッション・同一番号の再保存が拒否されることを確認します。
    func testDuplicateGapOrdinalIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, cause: .linkLost), for: fixtures.sessionID)
        let before = try fixtures.gaps.gaps(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, cause: .bufferOverflow), for: fixtures.sessionID)
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), before)
    }

    /// 前後セグメントが存在しない空白は `integrityConflict` で、行は増えません。
    ///
    /// 責務: 直前・直後のいずれの不在も拒否し、別セッションにだけあるセグメントも不在扱いになることを確認します。
    func testMissingPrecedingOrFollowingSegmentIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        let other = try fixtures.makeOtherSession()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 7), for: other)
        let invalid = [
            GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, preceding: 5),
            GRDBSegmentationRepositoryFixtures.gap(ordinal: 1, preceding: 7),
            GRDBSegmentationRepositoryFixtures.gap(ordinal: 2, preceding: 0, following: 5),
            GRDBSegmentationRepositoryFixtures.gap(ordinal: 3, preceding: 0, following: 7)
        ]

        for gap in invalid {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                try fixtures.gaps.saveGap(gap, for: fixtures.sessionID)
            }
        }

        XCTAssertEqual(try fixtures.rowCounts().gaps, 0)
    }

    /// 開始より前の終了時刻は `integrityConflict` です(保存時・終了時とも)。
    ///
    /// 責務: 保存時は行が増えず、終了時は空白が未終了のまま残ることを確認します。
    func testEndBeforeStartIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        let start = Date(timeIntervalSince1970: 2_000)
        let reversed = GRDBSegmentationRepositoryFixtures.gap(ordinal: 0, startedAt: start, endedAt: Date(timeIntervalSince1970: 1_999.999999))
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.gaps.saveGap(reversed, for: fixtures.sessionID)
        }
        XCTAssertEqual(try fixtures.rowCounts().gaps, 0)
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 1, startedAt: start), for: fixtures.sessionID)
        let open = try fixtures.gaps.gaps(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.gaps.finishGap(
                ordinal: 1, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 1_999.999999), followingSegmentOrdinal: nil
            )
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), open)
    }

    /// 存在しない直後セグメントでの `finishGap` は `integrityConflict` で、空白は未終了のままです。
    ///
    /// 責務: 終了時の外部キー違反が分類され、更新が残らないことを確認します。
    func testFinishGapWithMissingFollowingSegmentIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        try fixtures.gaps.saveGap(GRDBSegmentationRepositoryFixtures.gap(ordinal: 0), for: fixtures.sessionID)
        let open = try fixtures.gaps.gaps(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.gaps.finishGap(
                ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 3_000), followingSegmentOrdinal: 9
            )
        }

        XCTAssertEqual(try fixtures.gaps.gaps(for: fixtures.sessionID), open)
    }
}
