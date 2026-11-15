import XCTest
@testable import ProjectZD8

/// `ELM327VehicleResponseClassifier` が `0100` の加工前応答を、ECU の正応答(`41 00`)を含むかどうかで分類することを検証します。
final class ELM327VehicleResponseClassifierTests: XCTestCase {
    /// 検証対象の分類器です。
    private let classifier = ELM327VehicleResponseClassifier()

    /// 応答ごとの分類結果を確認します。
    ///
    /// 責務: 各応答の分類が期待値と一致することを、応答を添えて検証します。
    /// - Parameters:
    ///   - responses: 加工前応答。
    ///   - expected: 期待する分類。
    private func assertClassified(_ responses: [String], as expected: VehicleResponseOutcome, file: StaticString = #filePath, line: UInt = #line) {
        for response in responses {
            XCTAssertEqual(classifier.classify(response), expected, "応答: \(response.debugDescription)", file: file, line: line)
        }
    }

    /// 正応答 `41 00 …` を含めば、空白の有無・大文字小文字・改行コード・プロンプトの違いによらず応答ありです。
    ///
    /// 責務: 表記揺れが分類を変えないことを確認します。
    func testPositiveResponseIsRespondingRegardlessOfFormatting() {
        assertClassified([
            "41 00 BE 3E B8 13",
            "4100BE3EB813",
            "41 00 be 3e b8 13",
            "41 00 BE 3E B8 13 \r\r>",
            "41 00 BE 3E B8 13\n>",
            "41 00 BE 3E B8 13\r\n>",
            "  41 00 BE 3E B8 13  ",
        ], as: .responding)
    }

    /// `SEARCHING...` の後に正応答が続けば応答ありです。
    ///
    /// 責務: プロトコル探索の表示が前置きされた正応答を確認します。
    func testSearchingFollowedByPositiveResponseIsResponding() {
        assertClassified(["SEARCHING...\r41 00 BE 3E B8 13\r\r>", "searching...\n4100BE3EB813\n>"], as: .responding)
    }

    /// ヘッダー付きの応答(11bit `7E8`、29bit `18DAF110`)も応答ありです。
    ///
    /// 責務: CAN ID とバイト数の前置きがあっても正応答を見つけることを確認します。
    func testHeaderedResponseIsResponding() {
        assertClassified(["7E8 06 41 00 BE 3E B8 13", "18DAF110 06 41 00 BE 3E B8 13\r>"], as: .responding)
    }

    /// ヘッダー付きで空白なし(`ATH1` かつ `ATS0`)の応答も、空白ありと同じく応答ありです。
    ///
    /// 責務: 仕様「空白の有無で結果が変わらない」「ヘッダー付き応答も応答あり」の組み合わせを確認します。
    func testHeaderedResponseWithoutSpacesIsResponding() {
        assertClassified(["7E806410098180001", "7E806410098180001\r>"], as: .responding)
    }

    /// 29bit ヘッダー付き・空白なし(`ATH1` かつ `ATS0`、`ATCP`/29bit CAN ID 8桁)の正応答は応答ありです。
    ///
    /// 責務: 8桁ヘッダーで偶数桁になる空白なしの行で、ヘッダーの後の `41 00` を見つけることを確認します。
    func testTwentyNineBitHeaderedResponseWithoutSpacesIsResponding() {
        assertClassified(["18DAF11006410098180001", "18DAF110064100BE3EB813\r>"], as: .responding)
    }

    /// 空白なしの16進行で、`4100` がバイト境界をまたぐ位置(奇数桁目から)にだけ現れる行は応答ありにしません。
    ///
    /// 責務: 偶数桁の行(先頭から2桁区切り)と、奇数桁の行(先頭3桁をヘッダーとして除いた後の2桁区切り)の両方で、
    /// 区切りがバイト境界に固定されることを確認します。
    func testSpacelessSequenceAcrossByteBoundaryIsNoResponse() {
        assertClassified(["04100BE3", "0410", "7E8004100B", "7E80410", "7E8041009"], as: .noResponse)
    }

    /// 空白なしの奇数桁の行でも、ヘッダーの後のバイト境界に `41 00` があれば応答ありです(上の境界テストの対)。
    ///
    /// 責務: 3桁ヘッダーを除いた後の先頭に `4100` が来る最短の行を確認します。
    func testSpacelessElevenBitHeaderFollowedByPositiveSequenceIsResponding() {
        assertClassified(["7E84100", "7E8064100"], as: .responding)
    }

    /// 空白なしのエラー表示(`NODATA`、`UNABLETOCONNECT`)は無応答です。
    ///
    /// 責務: `ATS0` でのエラー表示を応答ありにしないことを確認します。
    func testSpacelessErrorMessagesAreNoResponse() {
        assertClassified(["NODATA", "NODATA\r\r>", "UNABLETOCONNECT", "SEARCHING...\rUNABLETOCONNECT\r>", "nodata"], as: .noResponse)
    }

    /// 複数 ECU のうち1行でも正応答があれば応答ありです。
    ///
    /// 責務: 正応答でない行と正応答の行が混在する応答を確認します。
    func testAnyPositiveLineAmongSeveralIsResponding() {
        assertClassified(["NO DATA\r7E9 06 41 00 80 00 00 01\r>", "CAN ERROR\r41 00 00 00 00 01\r>"], as: .responding)
    }

    /// `41 00` が行の途中にある並びも正応答の並びとして扱います(DocC: 隣り合う2バイトで正応答の先頭を探す)。
    ///
    /// 責務: 行頭以外の `41 00` の扱いを DocC の契約どおりに固定します。
    func testAdjacentPositiveBytesInsideLineAreResponding() {
        assertClassified(["62 41 00 12"], as: .responding)
    }

    /// エラー表示・拒否・空応答は無応答です(大文字小文字によらない)。
    ///
    /// 責務: 仕様に挙げられた無応答の各形を確認します。
    func testErrorAndEmptyResponsesAreNoResponse() {
        assertClassified([
            "NO DATA\r\r>", "no data", "UNABLE TO CONNECT\r\r>", "SEARCHING...\r\r>", "SEARCHING...\rUNABLE TO CONNECT\r>",
            "BUS INIT: ...ERROR\r\r>", "BUS ERROR", "CAN ERROR\r>", "can error", "?\r\r>", "", ">", "\r\r>", "   ", " \r \n ",
        ], as: .noResponse)
    }

    /// 正応答でない 16 進応答(別 PID・別サービス・`41` だけ・奇数桁)は無応答です。
    ///
    /// 責務: `41 00` の並びが無い 16 進の行を応答ありにしないことを確認します。
    func testHexadecimalLinesWithoutPositiveSequenceAreNoResponse() {
        assertClassified(["41 01 00 07 E5 00", "7F 01 12", "41", "41 0", "00 41", "4 100"], as: .noResponse)
    }

    /// 16 進以外の文字を含む行は、`41 00` を含んでいても応答ありにしません。
    ///
    /// 責務: 文字列の行(エラー表示など)に紛れた `41 00` を正応答にしないことを確認します。
    func testNonHexadecimalLineContainingSequenceIsNoResponse() {
        assertClassified(["ERROR 41 00", "41 00 OK"], as: .noResponse)
    }
}
