import XCTest
@testable import ProjectZD8

/// サービス01の対応ビットマップの解読を検証します。
final class ELM327SupportBitmapTests: XCTestCase {
    /// 責務: 先頭範囲のビットをPID番号へ展開し、次範囲の有無を判定することを確認します。
    func testDecodesFirstRangeWithNextRange() throws {
        // BE 1F A8 13: PID 01,03,04,05,06,07,0C,0D,0E,0F,10,11,13,15,1C,1F,20
        let bitmap = try XCTUnwrap(ELM327SupportBitmap(base: 0x00, payload: [0xBE, 0x1F, 0xA8, 0x13]))
        XCTAssertEqual(bitmap.supportedPIDs, [0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F])
        XCTAssertTrue(bitmap.hasNextRange)
    }

    /// 責務: 次範囲ビットが無ければ走査を終えることを確認します。
    func testStopsWhenNextRangeBitIsClear() throws {
        let bitmap = try XCTUnwrap(ELM327SupportBitmap(base: 0x20, payload: [0x80, 0x00, 0x00, 0x00]))
        XCTAssertEqual(bitmap.supportedPIDs, [0x21])
        XCTAssertFalse(bitmap.hasNextRange)
    }

    /// 責務: 範囲先頭が0x20の倍数でも、範囲を示すPID自体はデータPIDに含めないことを確認します。
    func testExcludesRangeMarkerPIDs() throws {
        let bitmap = try XCTUnwrap(ELM327SupportBitmap(base: 0x20, payload: [0x00, 0x00, 0x00, 0x01]))
        XCTAssertEqual(bitmap.supportedPIDs, [])
        XCTAssertTrue(bitmap.hasNextRange)
    }

    /// 責務: 4バイト未満のペイロードを解読しないことを確認します。
    func testRejectsShortPayload() {
        XCTAssertNil(ELM327SupportBitmap(base: 0x00, payload: [0xFF, 0xFF]))
    }
}
