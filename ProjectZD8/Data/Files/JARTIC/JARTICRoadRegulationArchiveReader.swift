import Foundation

/// JARTIC の配布 ZIP を読み、中の CSV を展開しながら1行ずつ解釈して渡す読み取り器です。
///
/// - ZIP の中のフォルダ以外で、名前が `.csv`(大小文字を区別しない)で終わるエントリがちょうど1つであることを求めます。
///   ほかのファイルは無視します。
/// - 展開・区切り・解釈を塊ごとに流すので、CSV 全体をメモリに載せません。
/// - 進捗は、読んだ圧縮バイトの累計と CSV の圧縮後の大きさで報告します(単調に増えます)。
/// - 取り消しは展開の塊ごとに確かめます(`ZipEntryInflater`)。
/// - 失敗の分類: ZIP の構造・CRC・方式・CSV の有無と数は `archiveInvalid`、見出し・版・行の長さ・引用符は `csvFormatChanged`。
///   取り消し(`CancellationError`)と `consume` が投げたエラーはそのまま伝えます。
nonisolated struct JARTICRoadRegulationArchiveReader: RoadRegulationArchiveReaderPort {
    /// 中央ディレクトリの読み取り器。
    private let directoryReader: ZipCentralDirectoryReader
    /// エントリの展開器。
    private let inflater: ZipEntryInflater

    /// 中央ディレクトリの読み取り器と展開器を受け取ります。
    ///
    /// 責務: ZIP を読む部品を保持します。
    /// - Parameters:
    ///   - directoryReader: 中央ディレクトリの読み取り器。
    ///   - inflater: エントリの展開器(バッファの大きさと展開後の上限を持ちます)。
    init(directoryReader: ZipCentralDirectoryReader = .init(), inflater: ZipEntryInflater = .init()) {
        self.directoryReader = directoryReader
        self.inflater = inflater
    }

    /// ZIP を読み、CSV の各行の解釈結果を順に渡します。
    ///
    /// 責務: 読み取りを実行し、失敗を取り込みのエラーへ分類します(`consume` の失敗は分類せずに伝えます)。
    /// - Parameters:
    ///   - url: 読む ZIP。
    ///   - progress: 読み取りの進み具合の通知。
    ///   - consume: 1行の解釈結果を受け取る処理。
    /// - Returns: 基準月(エントリ名から。読めなければ `nil`)・版(データ行が無ければ空文字)・データ行の数。
    /// - Throws: `RoadRegulationImportError.archiveInvalid` / `.csvFormatChanged`、`CancellationError`、`consume` のエラー。
    func read(
        archiveAt url: URL,
        progress: (RoadRegulationArchiveReadProgress) -> Void,
        consume: (RoadRegulationArchiveRecord) throws -> Void
    ) throws -> RoadRegulationArchiveSummary {
        do {
            return try readArchive(at: url, progress: progress, consume: consume)
        } catch let failure as ConsumerFailure {
            throw failure.underlying
        } catch {
            throw Self.importError(for: error)
        }
    }

    /// ZIP を開き、CSV のエントリを展開しながら区切って解釈します。
    ///
    /// 責務: エントリの選択、展開・区切り・解釈の連結、読み終えた時の情報の組み立てを行います。
    /// - Parameters:
    ///   - url: 読む ZIP。
    ///   - progress: 読み取りの進み具合の通知。
    ///   - consume: 1行の解釈結果を受け取る処理(失敗は `ConsumerFailure` で包みます)。
    /// - Returns: 読み終えた時に分かる情報。
    /// - Throws: 分類前の失敗。
    private func readArchive(
        at url: URL,
        progress: (RoadRegulationArchiveReadProgress) -> Void,
        consume: (RoadRegulationArchiveRecord) throws -> Void
    ) throws -> RoadRegulationArchiveSummary {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let entry = try csvEntry(in: file)
        let totalCompressedBytes = Int64(clamping: entry.compressedSize)
        var tokenizer = JARTICCSVTokenizer()
        var rows = JARTICArchiveRowStream()
        try inflater.stream(
            entry,
            from: file,
            progress: { read in
                progress(.init(processedCompressedBytes: Int64(clamping: read), totalCompressedBytes: totalCompressedBytes))
            },
            consume: { bytes in
                try tokenizer.consume(bytes) { row in try rows.accept(row) { try Self.forward($0, to: consume) } }
            }
        )
        try tokenizer.finish { row in try rows.accept(row) { try Self.forward($0, to: consume) } }
        try rows.requireHeader()
        return RoadRegulationArchiveSummary(
            dataMonth: Self.dataMonth(inEntryName: entry.pathBytes),
            formatVersion: rows.formatVersion ?? "",
            totalRows: rows.totalRows
        )
    }

    /// ZIP の中の CSV のエントリを1つ選びます。
    ///
    /// 責務: フォルダ以外のエントリから `.csv` で終わるものを数え、ちょうど1つであることを確かめます。
    /// - Parameter file: 読む ZIP。
    /// - Returns: CSV のエントリ。
    /// - Throws: `ZipArchiveError`、CSV が無ければ `noCSVEntry`、2つ以上なら `multipleCSVEntries`。
    private func csvEntry(in file: FileHandle) throws -> ZipArchiveEntry {
        let candidates = try directoryReader.entries(in: file).filter { Self.hasCSVExtension($0.pathBytes) }
        guard let entry = candidates.first else { throw JARTICArchiveFormatError.noCSVEntry }
        guard candidates.count == 1 else { throw JARTICArchiveFormatError.multipleCSVEntries }
        return entry
    }

    /// 1行の解釈結果を受け手へ渡し、受け手の失敗を包みます。
    ///
    /// 責務: 受け手の失敗を、形式の失敗と区別できるようにします(分類せずにそのまま伝えるため)。
    /// - Parameters:
    ///   - record: 1行の解釈結果。
    ///   - consume: 受け手。
    /// - Throws: 受け手の失敗を包んだ `ConsumerFailure`。
    private static func forward(
        _ record: RoadRegulationArchiveRecord,
        to consume: (RoadRegulationArchiveRecord) throws -> Void
    ) throws {
        do {
            try consume(record)
        } catch {
            throw ConsumerFailure(underlying: error)
        }
    }

    /// 名前のバイト列が `.csv`(大小文字を区別しない)で終わるかを判定します。
    ///
    /// 責務: 名前の文字コードに依らず、末尾の ASCII で拡張子を判定します。
    /// - Parameter pathBytes: エントリの名前のバイト列。
    /// - Returns: `.csv` で終われば `true`。
    private static func hasCSVExtension(_ pathBytes: [UInt8]) -> Bool {
        guard pathBytes.count >= csvExtension.count else { return false }
        let suffix = pathBytes.suffix(csvExtension.count).map { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 0x20 : byte
        }
        return suffix == csvExtension
    }

    /// エントリの名前から `_YYYYMM_k_` の形の基準月を読みます。
    ///
    /// 責務: 名前のバイト列を先頭から調べ、最初に見つかった有効な年月を返します(文字コードに依りません)。
    /// - Parameter pathBytes: エントリの名前のバイト列(例 `typeD_okinawa/沖縄県警_202609_k_2.1.csv`)。
    /// - Returns: 基準月。見つからなければ `nil`。
    static func dataMonth(inEntryName pathBytes: [UInt8]) -> RoadRegulationDataMonth? {
        let patternLength = 10
        guard pathBytes.count >= patternLength else { return nil }
        for start in 0...(pathBytes.count - patternLength) {
            if let month = dataMonth(in: pathBytes[start..<(start + patternLength)]) {
                return month
            }
        }
        return nil
    }

    /// 10バイトの並びが `_YYYYMM_k_` ならその年月を返します。
    ///
    /// 責務: 区切りの `_`・数字6桁・`_k_` の並びを確かめ、年月に直します。
    /// - Parameter window: 調べる10バイト。
    /// - Returns: 有効な年月。並びが違うか年月が範囲外なら `nil`。
    private static func dataMonth(in window: ArraySlice<UInt8>) -> RoadRegulationDataMonth? {
        let bytes = Array(window)
        guard bytes[0] == UInt8(ascii: "_"), Array(bytes[7..<10]) == Array("_k_".utf8) else { return nil }
        let digits = bytes[1..<7]
        guard digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else { return nil }
        return RoadRegulationDataMonth(yyyymm: String(decoding: digits, as: UTF8.self))
    }

    /// 読み取りの失敗を、取り込みのエラーへ分類します。
    ///
    /// 責務: ZIP と CSV の形式の失敗を `archiveInvalid` / `csvFormatChanged` に分け、取り消しはそのまま返します。
    /// - Parameter error: 分類前の失敗。
    /// - Returns: 呼び出し元へ投げるエラー。
    private static func importError(for error: any Error) -> any Error {
        switch error {
        case is CancellationError, is RoadRegulationImportError:
            return error
        case let format as JARTICArchiveFormatError:
            return [.noCSVEntry, .multipleCSVEntries].contains(format)
                ? RoadRegulationImportError.archiveInvalid
                : RoadRegulationImportError.csvFormatChanged
        case is JARTICCSVError:
            return RoadRegulationImportError.csvFormatChanged
        default:
            return RoadRegulationImportError.archiveInvalid
        }
    }

    /// 小文字の拡張子 `.csv` のバイト列。
    private static let csvExtension = Array(".csv".utf8)

    /// `consume` が投げた失敗を、形式の失敗と区別して運ぶ包みです。
    private struct ConsumerFailure: Error {
        /// 受け手が投げた元の失敗。
        let underlying: any Error
    }
}
