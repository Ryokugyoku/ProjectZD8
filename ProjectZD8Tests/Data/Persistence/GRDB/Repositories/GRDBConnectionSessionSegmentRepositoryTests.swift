import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionSegmentRepository` の保存・終了・読込・エラー分類を仕様から検証します。
final class GRDBConnectionSessionSegmentRepositoryTests: XCTestCase {
    /// 検証対象の組立てです。
    private func makeFixtures() throws -> GRDBSegmentationRepositoryFixtures {
        try GRDBSegmentationRepositoryFixtures()
    }

    // MARK: - beginSegment / segments(for:)

    /// 未終了区間は保存して等しく読めます。
    ///
    /// 責務: 1件の未終了区間の往復一致を確認します。
    func testBeginSegmentRoundTripsOpenSegment() throws {
        let fixtures = try makeFixtures()
        let segment = GRDBSegmentationRepositoryFixtures.segment(
            ordinal: 0, startReason: .reconnected, mode: .canMonitor,
            startedAt: Date(timeIntervalSince1970: 1_000.5), anchor: 77, firstSequence: 3
        )

        try fixtures.segments.beginSegment(segment, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), [segment])
    }

    /// 時刻はマイクロ秒精度へ最近傍丸めで保存されます。
    ///
    /// 責務: 開始時刻の0.4マイクロ秒端数が切り捨てられ、0.6マイクロ秒端数が切り上げられることを確認します。
    func testStartTimeIsRoundedToNearestMicrosecond() throws {
        let fixtures = try makeFixtures()
        let down = GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, startedAt: Date(timeIntervalSince1970: 100.0000004))
        let up = GRDBSegmentationRepositoryFixtures.segment(ordinal: 1, startedAt: Date(timeIntervalSince1970: 100.0000006))

        try fixtures.segments.beginSegment(down, for: fixtures.sessionID)
        try fixtures.segments.beginSegment(up, for: fixtures.sessionID)

        let loaded = try fixtures.segments.segments(for: fixtures.sessionID)
        XCTAssertEqual(loaded.map(\.startedAt), [Date(timeIntervalSince1970: 100.0), Date(timeIntervalSince1970: 100.000001)])
    }

    /// 区間は `segmentOrdinal` 昇順で返ります。
    ///
    /// 責務: 保存順が逆でも昇順で読めることを確認します。
    func testSegmentsAreReturnedInAscendingOrdinalOrder() throws {
        let fixtures = try makeFixtures()
        for ordinal in [2, 0, 1] {
            try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: ordinal), for: fixtures.sessionID)
        }

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID).map(\.segmentOrdinal), [0, 1, 2])
    }

    /// 他セッションと存在しないセッションの区間は混ざりません。
    ///
    /// 責務: セッション単位の絞り込みと、行のないセッションで空配列になることを確認します。
    func testSegmentsAreScopedToSession() throws {
        let fixtures = try makeFixtures()
        let other = try fixtures.makeOtherSession()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: fixtures.sessionID)
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, anchor: 99), for: other)

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID).map(\.monotonicAnchorNanoseconds), [5])
        XCTAssertEqual(try fixtures.segments.segments(for: other).map(\.monotonicAnchorNanoseconds), [99])
        XCTAssertEqual(try fixtures.segments.segments(for: ConnectionSessionID()), [])
    }

    /// 4つの開始理由と2つの取得モードがすべて往復します。
    ///
    /// 責務: 開始理由×取得モード(4×2)の全組み合わせの保存と読込を確認します。
    func testAllStartReasonsAndAcquisitionModesRoundTrip() throws {
        let fixtures = try makeFixtures()
        let reasons: [ConnectionSessionSegmentStartReason] = [.initial, .reconnected, .processRelaunched, .modeSwitched]
        let modes: [ConnectionSessionAcquisitionMode] = [.pidPolling, .canMonitor]
        var expected: [ConnectionSessionSegment] = []
        for reason in reasons {
            for mode in modes {
                expected.append(GRDBSegmentationRepositoryFixtures.segment(ordinal: expected.count, startReason: reason, mode: mode))
            }
        }

        for segment in expected {
            try fixtures.segments.beginSegment(segment, for: fixtures.sessionID)
        }

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), expected)
    }

    // MARK: - finishSegment

    /// 終了すると終了時刻・終了理由・`lastSequence` が反映されます。
    ///
    /// 責務: `finishSegment` 後の読込値を確認します(他の項目は不変)。
    func testFinishSegmentAppliesEndInformation() throws {
        let fixtures = try makeFixtures()
        let open = GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, firstSequence: 4)
        try fixtures.segments.beginSegment(open, for: fixtures.sessionID)

        try fixtures.segments.finishSegment(
            ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 1_500.25), reason: .linkLost, lastSequence: 9
        )

        let loaded = try XCTUnwrap(try fixtures.segments.segments(for: fixtures.sessionID).first)
        XCTAssertEqual(loaded.endedAt, Date(timeIntervalSince1970: 1_500.25))
        XCTAssertEqual(loaded.endReason, .linkLost)
        XCTAssertEqual(loaded.lastSequence, 9)
        XCTAssertEqual(loaded.startReason, open.startReason)
        XCTAssertEqual(loaded.firstSequence, 4)
        XCTAssertEqual(loaded.monotonicAnchorNanoseconds, 5)
    }

    /// `lastSequence` が `nil` でも終了できます。
    ///
    /// 責務: フレームを持たない区間の終了を `nil` のまま読めることを確認します。
    func testFinishSegmentAllowsNilLastSequence() throws {
        let fixtures = try makeFixtures()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: fixtures.sessionID)

        try fixtures.segments.finishSegment(
            ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 1_000), reason: .sessionEnded, lastSequence: nil
        )

        let loaded = try XCTUnwrap(try fixtures.segments.segments(for: fixtures.sessionID).first)
        XCTAssertEqual(loaded.endReason, .sessionEnded)
        XCTAssertNil(loaded.lastSequence)
        XCTAssertEqual(loaded.endedAt, loaded.startedAt)
    }

    /// 7つの終了理由がすべて往復します。
    ///
    /// 責務: 終了理由ごとに区間を終了し、読込値が一致することを確認します。
    func testAllEndReasonsRoundTrip() throws {
        let fixtures = try makeFixtures()
        let reasons: [ConnectionSessionSegmentEndReason] = [
            .linkLost, .processTerminated, .responseStall, .adapterBufferFull, .bufferOverflow, .modeSwitched, .sessionEnded
        ]

        for (ordinal, reason) in reasons.enumerated() {
            try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: ordinal), for: fixtures.sessionID)
            try fixtures.segments.finishSegment(
                ordinal: ordinal, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_000), reason: reason, lastSequence: 1
            )
        }

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID).map(\.endReason), reasons.map { Optional($0) })
    }

    // MARK: - invalidState

    /// 終了情報を持つ区間の `beginSegment` は `invalidState` で、行は増えません。
    ///
    /// 責務: 終了時刻・終了理由・`lastSequence` のいずれかを持つ区間を拒否することを確認します。
    func testBeginSegmentWithEndInformationIsInvalidState() throws {
        let fixtures = try makeFixtures()
        let ended = ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling, startedAt: Date(timeIntervalSince1970: 1),
            monotonicAnchorNanoseconds: 0, firstSequence: 0, endedAt: Date(timeIntervalSince1970: 2),
            endReason: .linkLost, lastSequence: 1
        )
        let reasonOnly = ConnectionSessionSegment(
            segmentOrdinal: 1, startReason: .initial, acquisitionMode: .pidPolling, startedAt: Date(timeIntervalSince1970: 1),
            monotonicAnchorNanoseconds: 0, firstSequence: 0, endReason: .linkLost
        )
        let lastOnly = ConnectionSessionSegment(
            segmentOrdinal: 2, startReason: .initial, acquisitionMode: .pidPolling, startedAt: Date(timeIntervalSince1970: 1),
            monotonicAnchorNanoseconds: 0, firstSequence: 0, lastSequence: 3
        )

        for segment in [ended, reasonOnly, lastOnly] {
            assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
                try fixtures.segments.beginSegment(segment, for: fixtures.sessionID)
            }
        }

        XCTAssertEqual(try fixtures.rowCounts().segments, 0)
    }

    /// 存在しない区間の `finishSegment` は `invalidState` です。
    ///
    /// 責務: 番号違い・別セッションの区間に対する終了が拒否され、行が変わらないことを確認します。
    func testFinishMissingSegmentIsInvalidState() throws {
        let fixtures = try makeFixtures()
        let other = try fixtures.makeOtherSession()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: other)
        let before = try fixtures.segments.segments(for: other)

        for (ordinal, session) in [(0, fixtures.sessionID), (5, other)] {
            assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
                try fixtures.segments.finishSegment(
                    ordinal: ordinal, for: session, endedAt: Date(timeIntervalSince1970: 2_000), reason: .linkLost, lastSequence: nil
                )
            }
        }

        XCTAssertEqual(try fixtures.segments.segments(for: other), before)
        XCTAssertEqual(try fixtures.rowCounts().segments, 1)
    }

    /// 終了済み区間の `finishSegment` は `invalidState` で、先の終了情報が保たれます。
    ///
    /// 責務: 二重終了が上書きではなく拒否されることを確認します。
    func testFinishAlreadyFinishedSegmentIsInvalidState() throws {
        let fixtures = try makeFixtures()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: fixtures.sessionID)
        try fixtures.segments.finishSegment(
            ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_000), reason: .linkLost, lastSequence: 5
        )
        let finished = try fixtures.segments.segments(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.invalidState) {
            try fixtures.segments.finishSegment(
                ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 3_000), reason: .sessionEnded, lastSequence: 6
            )
        }

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), finished)
    }

    // MARK: - integrityConflict

    /// 番号重複は `integrityConflict` で、既存行は変わりません。
    ///
    /// 責務: 同一セッション・同一番号の再保存が拒否され、行が増減・変更しないことを確認します。
    func testDuplicateOrdinalIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, anchor: 1), for: fixtures.sessionID)
        let before = try fixtures.segments.segments(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.segments.beginSegment(
                GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, anchor: 2), for: fixtures.sessionID
            )
        }

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), before)
    }

    /// 親セッションがない区間は `integrityConflict` で、行は増えません。
    ///
    /// 責務: 存在しないセッションIDへの保存が拒否されることを確認します。
    func testBeginSegmentForMissingSessionIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(), for: ConnectionSessionID())
        }

        XCTAssertEqual(try fixtures.rowCounts().segments, 0)
    }

    /// `Int64` に収まらない単調時計アンカーは `integrityConflict` で、行は増えません。
    ///
    /// 責務: `Int64.max + 1` を拒否し、`Int64.max` を受理することを確認します。
    func testAnchorBeyondInt64IsIntegrityConflict() throws {
        let fixtures = try makeFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.segments.beginSegment(
                GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, anchor: UInt64(Int64.max) + 1), for: fixtures.sessionID
            )
        }
        XCTAssertEqual(try fixtures.rowCounts().segments, 0)
        try fixtures.segments.beginSegment(
            GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, anchor: UInt64(Int64.max)), for: fixtures.sessionID
        )
        XCTAssertEqual(try fixtures.rowCounts().segments, 1)
    }

    /// 開始より前の終了時刻は `integrityConflict` で、区間は未終了のままです。
    ///
    /// 責務: 開始より1マイクロ秒前の終了を拒否し、開始と同時刻の終了は受理することを確認します。
    func testEndBeforeStartIsIntegrityConflictAndLeavesSegmentOpen() throws {
        let fixtures = try makeFixtures()
        let start = Date(timeIntervalSince1970: 1_000)
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, startedAt: start), for: fixtures.sessionID)
        let open = try fixtures.segments.segments(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.segments.finishSegment(
                ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 999.999999), reason: .linkLost, lastSequence: nil
            )
        }
        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), open)
        try fixtures.segments.finishSegment(ordinal: 0, for: fixtures.sessionID, endedAt: start, reason: .linkLost, lastSequence: nil)

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID).first?.endedAt, start)
    }

    /// `firstSequence` 未満の `lastSequence` は `integrityConflict` で、区間は未終了のままです。
    ///
    /// 責務: 1小さい値を拒否し、同値は受理することを確認します。
    func testLastSequenceBelowFirstSequenceIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0, firstSequence: 10), for: fixtures.sessionID)
        let open = try fixtures.segments.segments(for: fixtures.sessionID)

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.segments.finishSegment(
                ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_000), reason: .linkLost, lastSequence: 9
            )
        }
        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID), open)
        try fixtures.segments.finishSegment(
            ordinal: 0, for: fixtures.sessionID, endedAt: Date(timeIntervalSince1970: 2_000), reason: .linkLost, lastSequence: 10
        )

        XCTAssertEqual(try fixtures.segments.segments(for: fixtures.sessionID).first?.lastSequence, 10)
    }
}
