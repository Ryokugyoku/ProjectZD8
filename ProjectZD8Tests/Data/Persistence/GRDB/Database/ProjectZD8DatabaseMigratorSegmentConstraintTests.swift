import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `connection_session_segments` の主キー・列挙値CHECK・範囲CHECK・終了状態CHECKを直接INSERTで検証します。
final class ProjectZD8DatabaseMigratorSegmentConstraintTests: XCTestCase {
    /// 開始理由として許可される保存値です。
    private static let startReasons = ["initial", "reconnected", "processRelaunched", "modeSwitched"]
    /// 終了理由として許可される保存値です。
    private static let endReasons = [
        "linkLost", "processTerminated", "responseStall", "adapterBufferFull",
        "bufferOverflow", "modeSwitched", "sessionEnded"
    ]

    /// 既定値のセグメントは挿入できます。
    ///
    /// 責務: 以降の拒否テストの対照として、既定値の行が制約を満たすことを確認します。
    func testDefaultOpenSegmentIsAccepted() throws {
        let fixtures = try SegmentationSchemaFixtures()

        try fixtures.queue.write { database in
            try fixtures.insertSession(database)
            try fixtures.insertSegment(database)
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 1)
    }

    /// 主キーは (sessionID, segmentOrdinal) です。
    ///
    /// 責務: 同一セッション内の番号重複は拒否し、別セッションの同じ番号は許可することを確認します。
    func testPrimaryKeyIsSessionAndSegmentOrdinal() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database)
            try fixtures.insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertSegment(database, ordinal: 4)
        }

        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 4) }
        try fixtures.queue.write { try fixtures.insertSegment($0, session: SegmentationSchemaFixtures.sessionB, ordinal: 4) }

        XCTAssertEqual(try fixtures.rowCount(.segments), 2)
    }

    /// 親セッションが存在しないセグメントは外部キーで拒否されます。
    ///
    /// 責務: `sessionID` の外部キーが有効であることを確認します。
    func testSegmentWithoutParentSessionIsRejected() throws {
        let fixtures = try SegmentationSchemaFixtures()

        fixtures.assertRejected { try fixtures.insertSegment($0) }

        XCTAssertEqual(try fixtures.rowCount(.segments), 0)
    }

    /// 開始理由は4値だけ許可されます。
    ///
    /// 責務: 4つの許可値の受理と、一覧にない値・大文字小文字違い・空文字の拒否を確認します。
    func testStartReasonAcceptsOnlyListedValues() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        for (index, value) in Self.startReasons.enumerated() {
            try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: Int64(index), startReason: value) }
        }

        for invalid in ["Initial", "linkLost", "", "unknown"] {
            fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 99, startReason: invalid) }
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), Self.startReasons.count)
    }

    /// 取得モードは2値だけ許可されます。
    ///
    /// 責務: `pidPolling` / `canMonitor` の受理と、一覧にない値の拒否を確認します。
    func testAcquisitionModeAcceptsOnlyListedValues() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        for (index, value) in ["pidPolling", "canMonitor"].enumerated() {
            try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: Int64(index), mode: value) }
        }

        for invalid in ["PidPolling", "polling", "", "can"] {
            fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 99, mode: invalid) }
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 2)
    }

    /// 終了理由は7値だけ許可されます。
    ///
    /// 責務: 7つの許可値の受理と、一覧にない値・開始理由専用の値の拒否を確認します。
    func testEndReasonAcceptsOnlyListedValues() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }
        for (index, value) in Self.endReasons.enumerated() {
            try fixtures.queue.write {
                try fixtures.insertSegment($0, ordinal: Int64(index), endedAt: 2_000, endReason: value)
            }
        }

        for invalid in ["initial", "reconnected", "", "unknown"] {
            fixtures.assertRejected {
                try fixtures.insertSegment($0, ordinal: 99, endedAt: 2_000, endReason: invalid)
            }
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), Self.endReasons.count)
    }

    /// 終了時刻と終了理由は両方NULLか両方非NULLです。
    ///
    /// 責務: 片方だけがある行の拒否と、両方ある行・両方ない行の受理を確認します。
    func testEndTimeAndEndReasonMustBePresentTogether() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 1, endedAt: 2_000, endReason: nil) }
        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 2, endedAt: nil, endReason: "linkLost") }
        try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: 3, endedAt: 2_000, endReason: "linkLost") }
        try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: 4) }

        XCTAssertEqual(try fixtures.rowCount(.segments), 2)
    }

    /// 未終了のセグメントは `lastSequence` を持てません。
    ///
    /// 責務: 未終了で `lastSequence` がある行の拒否と、終了済みで `lastSequence` がNULLの行の受理を確認します。
    func testOpenSegmentCannotHaveLastSequence() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 1, lastSequence: 5) }
        try fixtures.queue.write {
            try fixtures.insertSegment($0, ordinal: 2, endedAt: 2_000, endReason: "sessionEnded", lastSequence: nil)
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 1)
    }

    /// 終了時刻は開始時刻以上です。
    ///
    /// 責務: 開始より1マイクロ秒前の拒否と、開始と同時刻の受理を確認します。
    func testEndTimeMustNotPrecedeStartTime() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected {
            try fixtures.insertSegment($0, ordinal: 1, startedAt: 1_000, endedAt: 999, endReason: "linkLost")
        }
        try fixtures.queue.write {
            try fixtures.insertSegment($0, ordinal: 2, startedAt: 1_000, endedAt: 1_000, endReason: "linkLost")
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 1)
    }

    /// `lastSequence` は `firstSequence` 以上です。
    ///
    /// 責務: 1小さい値の拒否と、同値・より大きい値の受理を確認します。
    func testLastSequenceMustNotPrecedeFirstSequence() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected {
            try fixtures.insertSegment(
                $0, ordinal: 1, firstSequence: 10, endedAt: 2_000, endReason: "linkLost", lastSequence: 9
            )
        }
        for (ordinal, last) in [(Int64(2), Int64(10)), (3, 11)] {
            try fixtures.queue.write {
                try fixtures.insertSegment(
                    $0, ordinal: ordinal, firstSequence: 10, endedAt: 2_000, endReason: "linkLost", lastSequence: last
                )
            }
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 2)
    }

    /// 番号・先頭記録順序・単調時計アンカーは0以上です。
    ///
    /// 責務: 各列で-1の拒否と0の受理を確認します。
    func testOrdinalFirstSequenceAndAnchorMustBeNonNegative() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { try fixtures.insertSession($0) }

        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: -1) }
        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 1, firstSequence: -1) }
        fixtures.assertRejected { try fixtures.insertSegment($0, ordinal: 2, anchor: -1) }
        try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: 0, anchor: 0, firstSequence: 0) }

        XCTAssertEqual(try fixtures.rowCount(.segments), 1)
    }
}
