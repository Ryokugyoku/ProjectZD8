import Foundation
import XCTest
@testable import ProjectZD8

/// `AdapterLinkPromptBuffer` の上限付きの溜め込みと、プロンプト `>` 単位の切り出しを検証します。
final class AdapterLinkPromptBufferTests: XCTestCase {
    /// 文字列をバイト列にします。
    ///
    /// 責務: テストの入力を UTF-8 のバイト列へ変換します。
    /// - Parameter text: 文字列。
    /// - Returns: バイト列。
    private func data(_ text: String) -> Data { Data(text.utf8) }

    /// 最初の `>` までを `>` を含めて切り出し、残りを次へ残します。
    ///
    /// 責務: 1回の切り出しの範囲と、残りのバイトを確認します。
    func testTakeThroughPromptReturnsUpToFirstPromptInclusive() {
        var buffer = AdapterLinkPromptBuffer(capacity: 64)
        XCTAssertTrue(buffer.append(data("41 00\r>REST")))

        XCTAssertEqual(buffer.takeThroughPrompt(), data("41 00\r>"))
        XCTAssertEqual(buffer.bytes, data("REST"))
        XCTAssertNil(buffer.takeThroughPrompt())
    }

    /// 分割して届いた応答は、`>` が届いた時に1件として切り出せます。
    ///
    /// 責務: `>` が届く前は切り出せず、届いた後に連結した応答になることを確認します。
    func testSplitArrivalIsJoinedWhenPromptArrives() {
        var buffer = AdapterLinkPromptBuffer(capacity: 64)
        XCTAssertTrue(buffer.append(data("41 0")))
        XCTAssertNil(buffer.takeThroughPrompt())
        XCTAssertTrue(buffer.append(data("0 BE")))
        XCTAssertNil(buffer.takeThroughPrompt())
        XCTAssertTrue(buffer.append(data("\r>")))

        XCTAssertEqual(buffer.takeThroughPrompt(), data("41 00 BE\r>"))
        XCTAssertTrue(buffer.bytes.isEmpty)
    }

    /// 1回の受信に複数の応答があれば、届いた順に1件ずつ切り出せます。
    ///
    /// 責務: 応答が混ざらず順に取り出されることを確認します。
    func testMultipleResponsesInOneArrivalAreTakenInOrder() {
        var buffer = AdapterLinkPromptBuffer(capacity: 64)
        XCTAssertTrue(buffer.append(data("FIRST\r>SECOND\r>")))

        XCTAssertEqual(buffer.takeThroughPrompt(), data("FIRST\r>"))
        XCTAssertEqual(buffer.takeThroughPrompt(), data("SECOND\r>"))
        XCTAssertNil(buffer.takeThroughPrompt())
    }

    /// 上限ちょうどまでは溜められ、超える追加は溜めずに失敗します。
    ///
    /// 責務: 上限の境界と、失敗した追加が既存の内容を変えないことを確認します。
    func testAppendRespectsCapacityBoundary() {
        var buffer = AdapterLinkPromptBuffer(capacity: 4)
        XCTAssertTrue(buffer.append(data("AB")))
        XCTAssertTrue(buffer.append(data("CD")))
        XCTAssertFalse(buffer.append(data("E")))
        XCTAssertEqual(buffer.bytes, data("ABCD"))

        var single = AdapterLinkPromptBuffer(capacity: 4)
        XCTAssertFalse(single.append(data("ABCDE")))
        XCTAssertTrue(single.bytes.isEmpty)
    }

    /// 1未満の上限は1として扱います。
    ///
    /// 責務: 0 と負の上限で1バイトだけ溜められることを確認します。
    func testCapacityBelowOneIsTreatedAsOne() {
        for capacity in [0, -5] {
            var buffer = AdapterLinkPromptBuffer(capacity: capacity)
            XCTAssertEqual(buffer.capacity, 1)
            XCTAssertTrue(buffer.append(data(">")))
            XCTAssertFalse(buffer.append(data(">")))
        }
    }

    /// `takeAll` はプロンプトの有無にかかわらず全バイトを返して空にし、`removeAll` は捨てます。
    ///
    /// 責務: 全取り出しと破棄の結果を確認します。
    func testTakeAllAndRemoveAll() {
        var buffer = AdapterLinkPromptBuffer(capacity: 64)
        XCTAssertTrue(buffer.append(data("PARTIAL")))
        XCTAssertEqual(buffer.takeAll(), data("PARTIAL"))
        XCTAssertTrue(buffer.bytes.isEmpty)
        XCTAssertEqual(buffer.takeAll(), Data())

        XCTAssertTrue(buffer.append(data("X\r>")))
        buffer.removeAll()
        XCTAssertNil(buffer.takeThroughPrompt())
        XCTAssertTrue(buffer.append(data("1234")))
    }

    /// プロンプトのバイト値は `>`(0x3E)です。
    ///
    /// 責務: 切り出しの区切りが ELM/STN のプロンプト文字であることを確認します。
    func testPromptByteIsGreaterThanSign() {
        XCTAssertEqual(AdapterLinkPromptBuffer.promptByte, Character(">").asciiValue)
    }
}
