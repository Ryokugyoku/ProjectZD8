import XCTest
@testable import ProjectZD8

/// 実車で確認したService 01応答形式の解析を検証します。
@MainActor
final class ELM327PIDResponseParserTests: XCTestCase {
    /// SEARCHING行を除いて冷却水温バイトを取り出します。
    ///
    /// 責務: 実車観測形式 `41 05 85` からデータバイト1件を保持することを確認します。
    func testParsesCoolantResponseAfterSearchingLine() throws {
        let bytes = try ELM327PIDResponseParser().parse(
            "SEARCHING...\r41 05 85\r",
            request: .init(service: 0x01, pid: 0x05)
        )

        XCTAssertEqual(bytes, [0x85])
    }

    /// 回転数応答の2データバイトを保持します。
    ///
    /// 責務: 実車観測形式 `41 0C 00 00` をゼロ値の成功応答として解析することを確認します。
    func testParsesZeroEngineSpeedResponse() throws {
        let bytes = try ELM327PIDResponseParser().parse(
            "41 0C 00 00\r",
            request: .init(service: 0x01, pid: 0x0C)
        )

        XCTAssertEqual(bytes, [0x00, 0x00])
    }

    /// 異なるPIDの応答を求めたPIDの成功にしません。
    ///
    /// 責務: 要求と一致しない正応答が形式不正として拒否されることを確認します。
    func testRejectsResponseForDifferentPID() {
        XCTAssertThrowsError(
            try ELM327PIDResponseParser().parse(
                "41 0C 00 00\r",
                request: .init(service: 0x01, pid: 0x05)
            )
        ) {
            XCTAssertEqual($0 as? OBDPIDTelemetryError, .malformedResponse)
        }
    }
}
