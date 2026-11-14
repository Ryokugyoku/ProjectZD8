import XCTest
@testable import ProjectZD8

/// CAN IDの11bit/29bit幅の判定と整形を検証します。
@MainActor
final class ELM327CANIdentifierWidthTests: XCTestCase {
    /// IDの値から幅を決める境界値を確認します。
    ///
    /// 責務: 0と0x7FFが11bit、0x800と0x1FFFFFFFが29bit、0x20000000がnilになることを確認します。
    func testInitFromIdentifierBoundaries() {
        XCTAssertEqual(ELM327CANIdentifierWidth(identifier: 0), .standard)
        XCTAssertEqual(ELM327CANIdentifierWidth(identifier: 0x7FF), .standard)
        XCTAssertEqual(ELM327CANIdentifierWidth(identifier: 0x800), .extended)
        XCTAssertEqual(ELM327CANIdentifierWidth(identifier: 0x1FFF_FFFF), .extended)
        XCTAssertNil(ELM327CANIdentifierWidth(identifier: 0x2000_0000))
        XCTAssertNil(ELM327CANIdentifierWidth(identifier: UInt32.max))
    }

    /// 真偽値から幅を決めます。
    ///
    /// 責務: `isExtended`の真偽が29bit/11bitに対応することを確認します。
    func testInitFromIsExtended() {
        XCTAssertEqual(ELM327CANIdentifierWidth(isExtended: true), .extended)
        XCTAssertEqual(ELM327CANIdentifierWidth(isExtended: false), .standard)
    }

    /// 各幅の最大値を確認します。
    ///
    /// 責務: `maximumValue`が0x7FF/0x1FFFFFFFであることを確認します。
    func testMaximumValue() {
        XCTAssertEqual(ELM327CANIdentifierWidth.standard.maximumValue, 0x7FF)
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.maximumValue, 0x1FFF_FFFF)
    }

    /// 各幅の16進桁数を確認します。
    ///
    /// 責務: `hexadecimalDigitCount`が3/8であることを確認します。
    func testHexadecimalDigitCount() {
        XCTAssertEqual(ELM327CANIdentifierWidth.standard.hexadecimalDigitCount, 3)
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.hexadecimalDigitCount, 8)
    }

    /// 11bit幅の包含判定の境界を確認します。
    ///
    /// 責務: 0x7FF以下だけを含み、0x800以上を含まないことを確認します。
    func testStandardContains() {
        XCTAssertTrue(ELM327CANIdentifierWidth.standard.contains(0))
        XCTAssertTrue(ELM327CANIdentifierWidth.standard.contains(0x7FF))
        XCTAssertFalse(ELM327CANIdentifierWidth.standard.contains(0x800))
        XCTAssertFalse(ELM327CANIdentifierWidth.standard.contains(0x2000_0000))
    }

    /// 29bit幅の包含判定の境界を確認します。
    ///
    /// 責務: 0x1FFFFFFF以下だけを含み、0x20000000以上を含まないことを確認します。
    func testExtendedContains() {
        XCTAssertTrue(ELM327CANIdentifierWidth.extended.contains(0))
        XCTAssertTrue(ELM327CANIdentifierWidth.extended.contains(0x800))
        XCTAssertTrue(ELM327CANIdentifierWidth.extended.contains(0x1FFF_FFFF))
        XCTAssertFalse(ELM327CANIdentifierWidth.extended.contains(0x2000_0000))
    }

    /// 16進文字列の桁数ゼロ埋めと大文字化を確認します。
    ///
    /// 責務: 11bitは3桁、29bitは8桁のゼロ埋め大文字16進になることを確認します。
    func testHexadecimalString() {
        XCTAssertEqual(ELM327CANIdentifierWidth.standard.hexadecimalString(0), "000")
        XCTAssertEqual(ELM327CANIdentifierWidth.standard.hexadecimalString(0x12), "012")
        XCTAssertEqual(ELM327CANIdentifierWidth.standard.hexadecimalString(0x7FF), "7FF")
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.hexadecimalString(0), "00000000")
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.hexadecimalString(0x7E8), "000007E8")
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.hexadecimalString(0x18DA_F110), "18DAF110")
        XCTAssertEqual(ELM327CANIdentifierWidth.extended.hexadecimalString(0x1FFF_FFFF), "1FFFFFFF")
    }
}
