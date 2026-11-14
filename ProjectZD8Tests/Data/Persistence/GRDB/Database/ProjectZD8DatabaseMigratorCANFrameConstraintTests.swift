import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `connection_session_can_frames` の主キー・識別子/payloadの範囲CHECK・セグメント外部キー・カスケード削除を検証します。
final class ProjectZD8DatabaseMigratorCANFrameConstraintTests: XCTestCase {
    /// 既定値のフレームは挿入できます。
    ///
    /// 責務: 以降の拒否テストの対照として、既定行が制約を満たすことを確認します。
    func testDefaultFrameIsAccepted() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()

        try fixtures.queue.write { try fixtures.insertFrame($0) }

        XCTAssertEqual(try fixtures.rowCount(.canFrames), 1)
    }

    /// 主キーは (sessionID, sequence) です。
    ///
    /// 責務: 同一セッション内の記録順序重複は拒否し、別セッションの同じ値は許可することを確認します。
    func testPrimaryKeyIsSessionAndSequence() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertSegment(database, session: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertFrame(database, sequence: 5)
        }

        fixtures.assertRejected { try fixtures.insertFrame($0, sequence: 5) }
        try fixtures.queue.write { try fixtures.insertFrame($0, session: SegmentationSchemaFixtures.sessionB, sequence: 5) }

        XCTAssertEqual(try fixtures.rowCount(.canFrames), 2)
    }

    /// CAN識別子は0以上0x1FFFFFFF以下です。
    ///
    /// 責務: 下限・上限の受理と、-1・上限+1の拒否を確認します。
    func testCANIdentifierBoundaries() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()

        try fixtures.queue.write { try fixtures.insertFrame($0, sequence: 0, identifier: 0) }
        try fixtures.queue.write { try fixtures.insertFrame($0, sequence: 1, identifier: 0x1FFF_FFFF) }
        fixtures.assertRejected { try fixtures.insertFrame($0, sequence: 2, identifier: -1) }
        fixtures.assertRejected { try fixtures.insertFrame($0, sequence: 3, identifier: 0x2000_0000) }

        XCTAssertEqual(try fixtures.rowCount(.canFrames), 2)
    }

    /// payloadは64バイト以下です。
    ///
    /// 責務: 0バイト・64バイトの受理と、65バイトの拒否を確認します。
    func testPayloadLengthBoundaries() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()

        try fixtures.queue.write { try fixtures.insertFrame($0, sequence: 0, payload: Data()) }
        try fixtures.queue.write { try fixtures.insertFrame($0, sequence: 1, payload: Data(count: 64)) }
        fixtures.assertRejected { try fixtures.insertFrame($0, sequence: 2, payload: Data(count: 65)) }

        XCTAssertEqual(try fixtures.rowCount(.canFrames), 2)
    }

    /// 所属セグメント番号は実在するセグメントを指します。
    ///
    /// 責務: 存在しない番号と、別セッションにだけ存在する番号の拒否を確認します。
    func testSegmentMustExistInSameSession() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.seedSessionWithSegment()
        try fixtures.queue.write { database in
            try fixtures.insertSession(database, id: SegmentationSchemaFixtures.sessionB)
            try fixtures.insertSegment(database, session: SegmentationSchemaFixtures.sessionB, ordinal: 7)
        }

        fixtures.assertRejected { try fixtures.insertFrame($0, segment: 5) }
        fixtures.assertRejected { try fixtures.insertFrame($0, segment: 7) }

        XCTAssertEqual(try fixtures.rowCount(.canFrames), 0)
    }

    /// セッション削除で3表の該当行がすべて消え、他セッションの行は残ります。
    ///
    /// 責務: `foreign_keys=ON` の接続での親セッション削除のカスケードと、他セッションへの非波及を確認します。
    func testDeletingSessionCascadesOnlyToItsOwnRows() throws {
        let fixtures = try SegmentationSchemaFixtures()
        try fixtures.queue.write { database in
            for session in [SegmentationSchemaFixtures.sessionA, SegmentationSchemaFixtures.sessionB] {
                try fixtures.insertSession(database, id: session)
                try fixtures.insertSegment(database, session: session, ordinal: 0)
                try fixtures.insertSegment(database, session: session, ordinal: 1)
                try fixtures.insertGap(database, session: session, ordinal: 0, preceding: 0, following: 1)
                try fixtures.insertFrame(database, session: session, sequence: 0, segment: 0)
                try fixtures.insertFrame(database, session: session, sequence: 1, segment: 1)
            }
        }
        XCTAssertEqual(try fixtures.rowCount(.segments), 4)

        try fixtures.queue.write { database in
            try database.execute(
                sql: "DELETE FROM connection_sessions WHERE id = ?",
                arguments: [SegmentationSchemaFixtures.sessionA]
            )
        }

        XCTAssertEqual(try fixtures.rowCount(.segments), 2)
        XCTAssertEqual(try fixtures.rowCount(.gaps), 1)
        XCTAssertEqual(try fixtures.rowCount(.canFrames), 2)
        let remaining = try fixtures.queue.read { database in
            try Set(String.fetchAll(database, sql: "SELECT sessionID FROM connection_session_can_frames"))
        }
        XCTAssertEqual(remaining, [SegmentationSchemaFixtures.sessionB])
    }
}
