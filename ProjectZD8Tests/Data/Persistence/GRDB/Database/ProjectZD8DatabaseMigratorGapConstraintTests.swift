import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `connection_session_gaps` の主キー・原因CHECK・時刻CHECK・前後セグメントの外部キーを直接INSERTで検証します。
final class ProjectZD8DatabaseMigratorGapConstraintTests: XCTestCase {
    /// 欠損原因として許可される保存値です。
    private static let causes = ["linkLost", "processTerminated", "responseStall", "adapterBufferFull", "bufferOverflow"]

    /// 既定値の欠損は挿入できます。
    ///
    /// 責務: 以降の拒否テストの対照として、未終了・直後なしの既定行が制約を満たすことを確認します。
    func testDefaultOpenGapIsAccepted() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()

        try fixtures.queue.write { try fixtures.insertGap($0) }

        XCTAssertEqual(try fixtures.rowCount(.gaps), 1)
    }

    /// 主キーは (sessionID, gapOrdinal) です。
    ///
    /// 責務: 同一セッション内の番号重複は拒否し、別セッションの同じ番号は許可することを確認します。
    func testPrimaryKeyIsSessionAndGapOrdinal() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertSegment(database, session: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertGap(database, ordinal: 2)
        }

        fixtures.assertRejected { try fixtures.insertGap($0, ordinal: 2) }
        try fixtures.queue.write { try fixtures.insertGap($0, session: SegmentationSchemaFixtures.sessionB, ordinal: 2) }

        XCTAssertEqual(try fixtures.rowCount(.gaps), 2)
    }

    /// 原因は5値だけ許可されます。
    ///
    /// 責務: 5つの許可値の受理と、セグメント終了理由にだけある値・不明値の拒否を確認します。
    func testCauseAcceptsOnlyListedValues() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        for (index, value) in Self.causes.enumerated() {
            try fixtures.queue.write { try fixtures.insertGap($0, ordinal: Int64(index), cause: value) }
        }

        for invalid in ["modeSwitched", "sessionEnded", "LinkLost", "", "unknown"] {
            fixtures.assertRejected { try fixtures.insertGap($0, ordinal: 99, cause: invalid) }
        }

        XCTAssertEqual(try fixtures.rowCount(.gaps), Self.causes.count)
    }

    /// 終了時刻はNULL可で、ある場合は開始時刻以上です。
    ///
    /// 責務: 開始より前の拒否と、開始と同時刻・NULLの受理を確認します。
    func testEndTimeIsOptionalAndMustNotPrecedeStartTime() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()

        fixtures.assertRejected { try fixtures.insertGap($0, ordinal: 1, startedAt: 2_000, endedAt: 1_999) }
        try fixtures.queue.write { try fixtures.insertGap($0, ordinal: 2, startedAt: 2_000, endedAt: 2_000) }
        try fixtures.queue.write { try fixtures.insertGap($0, ordinal: 3, startedAt: 2_000, endedAt: nil) }

        XCTAssertEqual(try fixtures.rowCount(.gaps), 2)
    }

    /// 直前セグメント番号は実在するセグメントを指します。
    ///
    /// 責務: 存在しない番号の拒否と、別セッションにだけ存在する番号の拒否を確認します。
    func testPrecedingSegmentMustExistInSameSession() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertSegment(database, session: SegmentationSchemaFixtures.sessionB, ordinal: 7)
        }

        fixtures.assertRejected { try fixtures.insertGap($0, preceding: 5) }
        fixtures.assertRejected { try fixtures.insertGap($0, preceding: 7) }

        XCTAssertEqual(try fixtures.rowCount(.gaps), 0)
    }

    /// 直後セグメント番号はNULL可で、ある場合は実在するセグメントを指します。
    ///
    /// 責務: 存在しない番号の拒否と、実在する番号・NULLの受理を確認します。
    func testFollowingSegmentIsOptionalButMustExist() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        try fixtures.queue.write { try fixtures.insertSegment($0, ordinal: 1) }

        fixtures.assertRejected { try fixtures.insertGap($0, ordinal: 1, following: 9) }
        try fixtures.queue.write { try fixtures.insertGap($0, ordinal: 2, following: 1) }
        try fixtures.queue.write { try fixtures.insertGap($0, ordinal: 3, following: nil) }

        XCTAssertEqual(try fixtures.rowCount(.gaps), 2)
    }
}
