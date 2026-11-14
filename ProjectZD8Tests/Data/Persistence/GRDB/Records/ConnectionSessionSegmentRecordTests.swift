import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionSegmentRecord` のDomainとの往復と、不正な保存値の復元拒否を検証します。
final class ConnectionSessionSegmentRecordTests: XCTestCase {
    /// テスト用のセッションIDです。
    private let sessionID = ConnectionSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!)

    /// 制約を満たすRecord行の既定値に上書きを適用して `Row` を作ります。
    ///
    /// 責務: 不正値を1項目だけ差し込んだ保存済み行を再現します。
    /// - Parameter overrides: 差し替える列。
    /// - Returns: Recordへ復元する行。
    private static func row(_ overrides: [String: (any DatabaseValueConvertible)?] = [:]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [
            "sessionID": "x", "segmentOrdinal": 2, "startReason": "reconnected", "acquisitionMode": "canMonitor",
            "startedAtMicroseconds": 1_000, "monotonicAnchorNanoseconds": 50, "firstSequence": 10,
            "endedAtMicroseconds": nil, "endReason": nil, "lastSequence": nil
        ]
        values.merge(overrides) { _, new in new }
        return Row(values)
    }

    /// 行から復元したDomain区間を返します。
    ///
    /// 責務: 指定上書きの行をRecordへ復元しDomainへ変換します。
    private static func restore(_ overrides: [String: (any DatabaseValueConvertible)?]) throws -> ConnectionSessionSegment {
        try ConnectionSessionSegmentRecord(row: row(overrides)).makeDomainSegment()
    }

    /// 未終了区間はDomain→Record→Domainで一致し、Record列は仕様値になります。
    ///
    /// 責務: 保存列(小文字UUID・マイクロ秒・列挙の文字列)と往復一致を確認します。
    func testOpenSegmentRoundTripsAndStoresSpecifiedColumns() throws {
        let segment = ConnectionSessionSegment(
            segmentOrdinal: 3, startReason: .processRelaunched, acquisitionMode: .canMonitor,
            startedAt: Date(timeIntervalSince1970: 100.000001), monotonicAnchorNanoseconds: 777, firstSequence: 42
        )

        let record = try ConnectionSessionSegmentRecord(segment: segment, sessionID: sessionID)

        XCTAssertEqual(record.sessionID, "00000000-0000-0000-0000-0000000000aa")
        XCTAssertEqual(record.segmentOrdinal, 3)
        XCTAssertEqual(record.startReason, "processRelaunched")
        XCTAssertEqual(record.acquisitionMode, "canMonitor")
        XCTAssertEqual(record.startedAtMicroseconds, 100_000_001)
        XCTAssertEqual(record.monotonicAnchorNanoseconds, 777)
        XCTAssertEqual(record.firstSequence, 42)
        XCTAssertNil(record.endedAtMicroseconds)
        XCTAssertNil(record.endReason)
        XCTAssertNil(record.lastSequence)
        XCTAssertEqual(try record.makeDomainSegment(), segment)
    }

    /// 終了済み区間はDomain→Record→Domainで一致します。
    ///
    /// 責務: 終了時刻・終了理由・`lastSequence`の保存列と往復一致を確認します。
    func testClosedSegmentRoundTrips() throws {
        let segment = ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: Date(timeIntervalSince1970: 10), monotonicAnchorNanoseconds: 0, firstSequence: 0,
            endedAt: Date(timeIntervalSince1970: 20.5), endReason: .sessionEnded, lastSequence: 0
        )

        let record = try ConnectionSessionSegmentRecord(segment: segment, sessionID: sessionID)

        XCTAssertEqual(record.endedAtMicroseconds, 20_500_000)
        XCTAssertEqual(record.endReason, "sessionEnded")
        XCTAssertEqual(record.lastSequence, 0)
        XCTAssertEqual(try record.makeDomainSegment(), segment)
    }

    /// Int64に収まらない単調時計アンカーは `integrityConflict` です。
    ///
    /// 責務: `Int64.max` は受理し、`Int64.max + 1` を拒否することを確認します。
    func testInitRejectsAnchorBeyondInt64() throws {
        func make(_ anchor: UInt64) throws -> ConnectionSessionSegmentRecord {
            try ConnectionSessionSegmentRecord(
                segment: ConnectionSessionSegment(
                    segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
                    startedAt: Date(timeIntervalSince1970: 1), monotonicAnchorNanoseconds: anchor, firstSequence: 0
                ),
                sessionID: sessionID
            )
        }

        XCTAssertEqual(try make(UInt64(Int64.max)).monotonicAnchorNanoseconds, Int64.max)
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) { _ = try make(UInt64(Int64.max) + 1) }
    }

    /// 範囲外・未知の列挙値・終了情報の不整合を持つ行は `integrityConflict` です。
    ///
    /// 責務: 復元時の各拒否条件を1項目ずつ確認します。
    func testRestoreRejectsInvalidRows() {
        let invalid: [[String: (any DatabaseValueConvertible)?]] = [
            ["segmentOrdinal": -1], ["startReason": "unknown"], ["acquisitionMode": "unknown"],
            ["monotonicAnchorNanoseconds": -1], ["firstSequence": -1],
            ["endedAtMicroseconds": 2_000, "endReason": nil],
            ["endedAtMicroseconds": nil, "endReason": "linkLost"],
            ["endedAtMicroseconds": 2_000, "endReason": "unknown"],
            ["endedAtMicroseconds": 999, "endReason": "linkLost"],
            ["lastSequence": 10],
            ["endedAtMicroseconds": 2_000, "endReason": "linkLost", "lastSequence": 9]
        ]

        for overrides in invalid {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try Self.restore(overrides)
            }
        }
    }

    /// 境界値の行は復元できます。
    ///
    /// 責務: 終了=開始、`lastSequence`=`firstSequence`、番号・順序・アンカー0の受理を確認します。
    func testRestoreAcceptsBoundaryRows() throws {
        let boundary = try Self.restore([
            "segmentOrdinal": 0, "firstSequence": 0, "monotonicAnchorNanoseconds": 0,
            "endedAtMicroseconds": 1_000, "endReason": "bufferOverflow", "lastSequence": 0
        ])

        XCTAssertEqual(boundary.endedAt, boundary.startedAt)
        XCTAssertEqual(boundary.lastSequence, 0)
        XCTAssertEqual(boundary.endReason, .bufferOverflow)
        XCTAssertEqual(try Self.restore([:]).segmentOrdinal, 2)
    }
}
