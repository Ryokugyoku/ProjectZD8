import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionMicrosecondTimestamp` の最近傍丸め・範囲検査・復元を分岐と境界値で検証します。
final class ConnectionSessionMicrosecondTimestampTests: XCTestCase {
    // MARK: - microseconds(for:)

    /// Unix epochは0マイクロ秒です。
    ///
    /// 責務: 基準時刻が0へ変換されることを確認します。
    func testEpochIsZeroMicroseconds() throws {
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: 0)), 0)
    }

    /// 正の時刻は整数マイクロ秒へ変換されます。
    ///
    /// 責務: 1.5秒と1マイクロ秒の変換値を確認します。
    func testPositiveTimesConvertToMicroseconds() throws {
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: 1.5)), 1_500_000)
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: 100.000001)), 100_000_001)
    }

    /// 負の時刻は符号付きマイクロ秒へ変換されます。
    ///
    /// 責務: epochより前の時刻が負値になることを確認します。
    func testNegativeTimesConvertToNegativeMicroseconds() throws {
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: -1.5)), -1_500_000)
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: -0.000001)), -1)
    }

    /// 0.5マイクロ秒未満は切り捨て、超える端数は切り上げです。
    ///
    /// 責務: 丸め境界の両側(±0.4・±0.6マイクロ秒)が最近傍へ丸められることを確認します。
    func testFractionsBelowAndAboveHalfMicrosecondRoundToNearest() throws {
        let cases: [(seconds: Double, expected: Int64)] = [
            (0.0000004, 0), (0.0000006, 1), (-0.0000004, 0), (-0.0000006, -1),
            (100.0000004, 100_000_000), (100.0000006, 100_000_001)
        ]

        for testCase in cases {
            let actual = try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: testCase.seconds))
            XCTAssertEqual(actual, testCase.expected, "\(testCase.seconds)")
        }
    }

    /// ちょうど0.5マイクロ秒の端数は0から遠い方へ丸められます。
    ///
    /// 責務: 2進で厳密に表せる1/128秒(7812.5マイクロ秒)の正負で同じ向きの丸めになることを確認します。
    func testExactHalfMicrosecondRoundsAwayFromZero() throws {
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: 1.0 / 128)), 7_813)
        XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: -1.0 / 128)), -7_813)
    }

    /// 非有限値は `integrityConflict` です。
    ///
    /// 責務: NaN・正負の無限大を成功へ潰さず拒否することを確認します。
    func testNonFiniteTimesAreRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: value))
            }
        }
    }

    /// Int64に収まらない時刻は `integrityConflict` です。
    ///
    /// 責務: 範囲外の正負の時刻を拒否し、範囲内の大きな時刻は受理することを確認します。
    func testOutOfRangeTimesAreRejectedAndLargeInRangeTimesAccepted() throws {
        for value in [1e13, -1e13, 1e300, -1e300] {
            assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                _ = try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: value))
            }
        }
        XCTAssertGreaterThan(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: 9.0e12)), 0)
        XCTAssertLessThan(try ConnectionSessionMicrosecondTimestamp.microseconds(for: Date(timeIntervalSince1970: -9.0e12)), 0)
    }

    // MARK: - date(fromMicroseconds:)

    /// マイクロ秒値から時刻を復元します。
    ///
    /// 責務: 0・正・負のマイクロ秒値が対応するepoch基準の時刻になることを確認します。
    func testDateFromMicroseconds() {
        XCTAssertEqual(ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: 0), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: 1_500_000), Date(timeIntervalSince1970: 1.5))
        XCTAssertEqual(ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: -2_000_000), Date(timeIntervalSince1970: -2))
        XCTAssertEqual(ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: 100_000_001), Date(timeIntervalSince1970: 100.000001))
    }

    /// マイクロ秒値は時刻を経由して往復しても変わりません。
    ///
    /// 責務: 代表値(負・0・大きな値)で `microseconds(for: date(fromMicroseconds:))` が恒等であることを確認します。
    func testMicrosecondValuesRoundTripThroughDate() throws {
        for value: Int64 in [-123_456_789_012, -1, 0, 1, 999_999, 1_700_000_000_123_456] {
            let date = ConnectionSessionMicrosecondTimestamp.date(fromMicroseconds: value)
            XCTAssertEqual(try ConnectionSessionMicrosecondTimestamp.microseconds(for: date), value)
        }
    }
}
