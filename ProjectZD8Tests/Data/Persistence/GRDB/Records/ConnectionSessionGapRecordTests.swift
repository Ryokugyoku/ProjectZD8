import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionGapRecord` のDomainとの往復と、不正な保存値の復元拒否を検証します。
final class ConnectionSessionGapRecordTests: XCTestCase {
    /// テスト用のセッションIDです。
    private let sessionID = ConnectionSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!)

    /// 制約を満たすRecord行の既定値に上書きを適用して `Row` を作ります。
    ///
    /// 責務: 不正値を1項目だけ差し込んだ保存済み行を再現します。
    /// - Parameter overrides: 差し替える列。
    /// - Returns: Recordへ復元する行。
    private static func row(_ overrides: [String: (any DatabaseValueConvertible)?] = [:]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [
            "sessionID": "x", "gapOrdinal": 1, "precedingSegmentOrdinal": 0, "followingSegmentOrdinal": nil,
            "startedAtMicroseconds": 2_000, "endedAtMicroseconds": nil, "cause": "linkLost"
        ]
        values.merge(overrides) { _, new in new }
        return Row(values)
    }

    /// 未終了の空白はDomain→Record→Domainで一致し、Record列は仕様値になります。
    ///
    /// 責務: 保存列と往復一致を確認します。
    func testOpenGapRoundTripsAndStoresSpecifiedColumns() throws {
        let gap = ConnectionSessionGap(
            gapOrdinal: 4, precedingSegmentOrdinal: 3, startedAt: Date(timeIntervalSince1970: 50.000001), cause: .responseStall
        )

        let record = try ConnectionSessionGapRecord(gap: gap, sessionID: sessionID)

        XCTAssertEqual(record.sessionID, "00000000-0000-0000-0000-0000000000bb")
        XCTAssertEqual(record.gapOrdinal, 4)
        XCTAssertEqual(record.precedingSegmentOrdinal, 3)
        XCTAssertNil(record.followingSegmentOrdinal)
        XCTAssertEqual(record.startedAtMicroseconds, 50_000_001)
        XCTAssertNil(record.endedAtMicroseconds)
        XCTAssertEqual(record.cause, "responseStall")
        XCTAssertEqual(try record.makeDomainGap(), gap)
    }

    /// 終了済みの空白はDomain→Record→Domainで一致します。
    ///
    /// 責務: 直後セグメント番号と終了時刻の保存と往復一致を確認します。
    func testClosedGapRoundTrips() throws {
        let gap = ConnectionSessionGap(
            gapOrdinal: 0, precedingSegmentOrdinal: 0, followingSegmentOrdinal: 1,
            startedAt: Date(timeIntervalSince1970: 5), endedAt: Date(timeIntervalSince1970: 6.25), cause: .bufferOverflow
        )

        let record = try ConnectionSessionGapRecord(gap: gap, sessionID: sessionID)

        XCTAssertEqual(record.followingSegmentOrdinal, 1)
        XCTAssertEqual(record.endedAtMicroseconds, 6_250_000)
        XCTAssertEqual(try record.makeDomainGap(), gap)
    }

    /// 表現範囲外の時刻を持つ空白は `integrityConflict` です。
    ///
    /// 責務: 開始・終了のどちらが範囲外でもRecord生成が拒否することを確認します。
    func testInitRejectsOutOfRangeTimes() {
        let tooLarge = Date(timeIntervalSince1970: 1e13)
        let invalid = [
            ConnectionSessionGap(gapOrdinal: 0, precedingSegmentOrdinal: 0, startedAt: tooLarge, cause: .linkLost),
            ConnectionSessionGap(
                gapOrdinal: 0, precedingSegmentOrdinal: 0, startedAt: Date(timeIntervalSince1970: 1),
                endedAt: tooLarge, cause: .linkLost
            )
        ]

        for gap in invalid {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try ConnectionSessionGapRecord(gap: gap, sessionID: sessionID)
            }
        }
    }

    /// 範囲外・未知の原因・時刻逆転を持つ行は `integrityConflict` です。
    ///
    /// 責務: 復元時の各拒否条件を1項目ずつ確認します。
    func testRestoreRejectsInvalidRows() {
        let invalid: [[String: (any DatabaseValueConvertible)?]] = [
            ["gapOrdinal": -1], ["precedingSegmentOrdinal": -1], ["followingSegmentOrdinal": -1],
            ["cause": "unknown"], ["cause": "sessionEnded"], ["endedAtMicroseconds": 1_999]
        ]

        for overrides in invalid {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try ConnectionSessionGapRecord(row: Self.row(overrides)).makeDomainGap()
            }
        }
    }

    /// 境界値の行は復元できます。
    ///
    /// 責務: 終了=開始、直後セグメントなし・0番、各番号0の受理を確認します。
    func testRestoreAcceptsBoundaryRows() throws {
        let gap = try ConnectionSessionGapRecord(row: Self.row([
            "gapOrdinal": 0, "precedingSegmentOrdinal": 0, "followingSegmentOrdinal": 0, "endedAtMicroseconds": 2_000
        ])).makeDomainGap()

        XCTAssertEqual(gap.endedAt, gap.startedAt)
        XCTAssertEqual(gap.followingSegmentOrdinal, 0)
        XCTAssertNil(try ConnectionSessionGapRecord(row: Self.row()).makeDomainGap().followingSegmentOrdinal)
    }
}
