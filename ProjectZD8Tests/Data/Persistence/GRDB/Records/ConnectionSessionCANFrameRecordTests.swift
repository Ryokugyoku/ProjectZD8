import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionCANFrameRecord` のDomainとの往復と、不正な保存値の復元拒否を検証します。
final class ConnectionSessionCANFrameRecordTests: XCTestCase {
    /// テスト用のセッションIDです。
    private let sessionID = ConnectionSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!)

    /// 制約を満たすRecord行の既定値に上書きを適用して `Row` を作ります。
    ///
    /// 責務: 不正値を1項目だけ差し込んだ保存済み行を再現します。
    /// - Parameter overrides: 差し替える列。
    /// - Returns: Recordへ復元する行。
    private static func row(_ overrides: [String: (any DatabaseValueConvertible)?] = [:]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [
            "sessionID": "x", "sequence": 5, "segmentOrdinal": 1, "receivedAtMicroseconds": 3_000,
            "monotonicNanoseconds": 9, "canIdentifier": 0x7E8, "payload": Data([1, 2, 3])
        ]
        values.merge(overrides) { _, new in new }
        return Row(values)
    }

    /// フレームはDomain→Record→Domainで一致し、Record列は仕様値になります。
    ///
    /// 責務: 保存列と往復一致を確認します。
    func testFrameRoundTripsAndStoresSpecifiedColumns() throws {
        let frame = CANFrameObservation(
            sequence: 7, segmentOrdinal: 2, receivedAt: Date(timeIntervalSince1970: 12.000001),
            monotonicNanoseconds: 123, canIdentifier: 0x18DA_F110, payload: [0xDE, 0xAD]
        )

        let record = try ConnectionSessionCANFrameRecord(frame: frame, sessionID: sessionID)

        XCTAssertEqual(record.sessionID, "00000000-0000-0000-0000-0000000000cc")
        XCTAssertEqual(record.sequence, 7)
        XCTAssertEqual(record.segmentOrdinal, 2)
        XCTAssertEqual(record.receivedAtMicroseconds, 12_000_001)
        XCTAssertEqual(record.monotonicNanoseconds, 123)
        XCTAssertEqual(record.canIdentifier, 0x18DA_F110)
        XCTAssertEqual(record.payload, Data([0xDE, 0xAD]))
        XCTAssertEqual(try record.makeDomainFrame(), frame)
    }

    /// 識別子と payload の境界値は往復できます。
    ///
    /// 責務: 識別子0・0x1FFFFFFF、payload 0・64バイトの受理を確認します。
    func testBoundaryIdentifiersAndPayloadsRoundTrip() throws {
        for (identifier, payload) in [
            (UInt32(0), [UInt8]()), (0x1FFF_FFFF, [UInt8](repeating: 0xAB, count: 64))
        ] {
            let frame = CANFrameObservation(
                sequence: 0, segmentOrdinal: 0, receivedAt: Date(timeIntervalSince1970: 0),
                monotonicNanoseconds: 0, canIdentifier: identifier, payload: payload
            )

            let restored = try ConnectionSessionCANFrameRecord(frame: frame, sessionID: sessionID).makeDomainFrame()

            XCTAssertEqual(restored, frame)
        }
    }

    /// Int64に収まらない単調時計値は `integrityConflict` です。
    ///
    /// 責務: `Int64.max` は受理し、`Int64.max + 1` を拒否することを確認します。
    func testInitRejectsMonotonicBeyondInt64() throws {
        func make(_ monotonic: UInt64) throws -> ConnectionSessionCANFrameRecord {
            try ConnectionSessionCANFrameRecord(
                frame: CANFrameObservation(
                    sequence: 0, segmentOrdinal: 0, receivedAt: Date(timeIntervalSince1970: 1),
                    monotonicNanoseconds: monotonic, canIdentifier: 1, payload: []
                ),
                sessionID: sessionID
            )
        }

        XCTAssertEqual(try make(UInt64(Int64.max)).monotonicNanoseconds, Int64.max)
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) { _ = try make(UInt64(Int64.max) + 1) }
    }

    /// 範囲外の値を持つ行は `integrityConflict` です。
    ///
    /// 責務: 復元時の各拒否条件(負値・識別子上限超過・payload 65バイト)を1項目ずつ確認します。
    func testRestoreRejectsInvalidRows() {
        let invalid: [[String: (any DatabaseValueConvertible)?]] = [
            ["sequence": -1], ["segmentOrdinal": -1], ["monotonicNanoseconds": -1], ["canIdentifier": -1],
            ["canIdentifier": 0x2000_0000], ["payload": Data(count: 65)]
        ]

        for overrides in invalid {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try ConnectionSessionCANFrameRecord(row: Self.row(overrides)).makeDomainFrame()
            }
        }
    }

    /// 境界値の行は復元できます。
    ///
    /// 責務: 各数値0、識別子0x1FFFFFFF、payload 64バイトの行が復元できることを確認します。
    func testRestoreAcceptsBoundaryRows() throws {
        let frame = try ConnectionSessionCANFrameRecord(row: Self.row([
            "sequence": 0, "segmentOrdinal": 0, "monotonicNanoseconds": 0,
            "canIdentifier": 0x1FFF_FFFF, "payload": Data(count: 64)
        ])).makeDomainFrame()

        XCTAssertEqual(frame.canIdentifier, 0x1FFF_FFFF)
        XCTAssertEqual(frame.payload.count, 64)
        XCTAssertEqual(frame.sequence, 0)
    }
}
