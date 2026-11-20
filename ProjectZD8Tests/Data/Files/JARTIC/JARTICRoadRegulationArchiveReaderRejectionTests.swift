import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRoadRegulationArchiveReader` が、形式の合わない ZIP と CSV を `archiveInvalid` / `csvFormatChanged` で拒むことを検証します。
@MainActor
final class JARTICRoadRegulationArchiveReaderRejectionTests: XCTestCase {
    private typealias Fixture = JARTICCSVFixture
    private typealias Row = JARTICCSVFixture.Row

    private var files: JARTICArchiveTemporaryFiles!

    override func setUp() async throws {
        try await super.setUp()
        files = try JARTICArchiveTemporaryFiles()
    }

    override func tearDown() async throws {
        files.removeAll()
        files = nil
        try await super.tearDown()
    }

    /// 責務: バイト列を一時ファイルへ書いて読み、指定の取り込みエラーで失敗することを確かめます。
    private func assertRejected(
        _ bytes: [UInt8],
        as expected: RoadRegulationImportError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = try files.write(bytes)
        XCTAssertThrowsError(
            try JARTICRoadRegulationArchiveReader().read(archiveAt: url, progress: { _ in }, consume: { _ in }),
            file: file, line: line
        ) { error in
            XCTAssertEqual(error as? RoadRegulationImportError, expected, "エラー: \(error)", file: file, line: line)
        }
    }

    /// 有効な行が2つある CSV です。
    private var validCSV: [UInt8] {
        Fixture.csv(Fixture.speedLimitRows(count: 2))
    }

    /// CSV のエントリが無い(フォルダと別の拡張子だけ)の ZIP は `archiveInvalid` です。
    ///
    /// 責務: CSV が0件の時の拒否を確認します。
    func testArchiveWithoutCSVIsInvalid() throws {
        let archive = TestZipArchiveBuilder(entries: [
            .directory(Fixture.okinawaFolderName),
            .file("typeD_okinawa/readme.txt", Array("not a csv".utf8)),
        ]).build()

        try assertRejected(archive, as: .archiveInvalid)
    }

    /// CSV のエントリが2つある ZIP は `archiveInvalid` です。
    ///
    /// 責務: CSV が2件以上の時の拒否を確認します。
    func testArchiveWithTwoCSVEntriesIsInvalid() throws {
        let archive = TestZipArchiveBuilder(entries: [
            .directory(Fixture.okinawaFolderName),
            Fixture.csvEntry(Fixture.okinawaEntryName, validCSV),
            Fixture.csvEntry("typeD_okinawa/沖縄県警_202608_k_2.1.csv", validCSV),
        ]).build()

        try assertRejected(archive, as: .archiveInvalid)
    }

    /// 見出しから必須の列が1つ欠けた CSV は `csvFormatChanged` です。
    ///
    /// 責務: 見出しが想定と違う時の拒否を確認します。
    func testHeaderMissingRequiredColumnIsFormatChange() throws {
        let header = Fixture.columnNames.map { $0 == JARTICColumnName.uniqueKey ? "別の列名" : $0 }
        let csv = Fixture.csv(Fixture.speedLimitRows(count: 2), header: header)

        try assertRejected(Fixture.archive(csv: csv), as: .csvFormatChanged)
    }

    /// 1行目のデータの版が `k_3.0` の CSV は `csvFormatChanged` です。
    ///
    /// 責務: 版が `k_2.` で始まらない時の拒否を確認します。
    func testUnsupportedFormatVersionIsFormatChange() throws {
        let rows = [Row(kind: 112, [JARTICColumnName.formatVersion: "k_3.0", JARTICColumnName.uniqueKey: "V3"])]

        try assertRejected(Fixture.archive(csv: Fixture.csv(rows)), as: .csvFormatChanged)
    }

    /// 引用の途中でファイルが終わる CSV は `csvFormatChanged` です。
    ///
    /// 責務: 区切りの失敗が CSV の形式の失敗として伝わることを確認します。
    func testUnterminatedQuoteIsFormatChange() throws {
        let csv = validCSV + Array("\"k_2.1\",\"112".utf8)

        try assertRejected(Fixture.archive(csv: csv), as: .csvFormatChanged)
    }

    /// 後半が切り取られた(EOCD の無い)ZIP は `archiveInvalid` です。
    ///
    /// 責務: 途中で切れた ZIP の拒否を確認します。
    func testTruncatedArchiveIsInvalid() throws {
        let archive = Fixture.archive(csv: validCSV)

        try assertRejected(Array(archive.prefix(archive.count / 2)), as: .archiveInvalid)
    }

    /// 圧縮データの途中で切れた(ヘッダーは正しい)エントリは `archiveInvalid` です。
    ///
    /// 責務: 展開の失敗が ZIP の失敗として伝わることを確認します。
    func testTruncatedCompressedDataIsInvalid() throws {
        var entry = Fixture.csvEntry(Fixture.okinawaEntryName, Fixture.csv(Fixture.speedLimitRows(count: 50)))
        entry.keepsCompressedPrefix = 40
        let archive = TestZipArchiveBuilder(entries: [.directory(Fixture.okinawaFolderName), entry]).build()

        try assertRejected(archive, as: .archiveInvalid)
    }

    /// CRC が中身と合わないエントリは `archiveInvalid` です。
    ///
    /// 責務: 検査値の不一致が ZIP の失敗として伝わることを確認します。
    func testChecksumMismatchIsInvalid() throws {
        var entry = Fixture.csvEntry(Fixture.okinawaEntryName, validCSV)
        entry.central.crc = 0x1234_5678
        entry.local.crc = 0x1234_5678
        let archive = TestZipArchiveBuilder(entries: [.directory(Fixture.okinawaFolderName), entry]).build()

        try assertRejected(archive, as: .archiveInvalid)
    }

    /// ZIP でないファイル(CSV をそのまま置いたもの)は `archiveInvalid` です。
    ///
    /// 責務: ZIP の署名が無い時の拒否を確認します。
    func testNonZipFileIsInvalid() throws {
        try assertRejected(validCSV, as: .archiveInvalid)
    }

    /// 中身が空(見出しも無い)の CSV は `csvFormatChanged` です。
    ///
    /// 責務: 見出しの無い CSV の拒否を確認します。
    func testEmptyCSVIsFormatChange() throws {
        try assertRejected(Fixture.archive(csv: []), as: .csvFormatChanged)
    }
}
