import Foundation
@testable import ProjectZD8

/// テストの ZIP を一時ファイルへ書き、製品の読み取り器と展開器で読み出す補助です。
nonisolated enum TestZipExtraction {
    /// 展開の結果です。
    struct Output {
        /// 連結した展開結果。
        var bytes: [UInt8] = []
        /// `progress` に渡された累計の列。
        var progress: [UInt64] = []
        /// 受け手へ渡った塊の大きさの列。
        var chunkSizes: [Int] = []
    }

    /// ZIP を最後まで読み出した結果の分類です。
    enum Outcome: Equatable, Sendable {
        /// エラーなく終わった。
        case succeeded
        /// ZIP のエラーで終わった。
        case zipError(ZipArchiveError)
        /// ZIP 以外のエラーで終わった(説明つき)。
        case otherError(String)
    }

    /// 補助自身の失敗です。
    enum SetupError: Error {
        /// ファイルのエントリが無い。
        case noFileEntry
    }

    /// 責務: バイト列を一時ファイルへ書いて読み込み用に開き、処理が終わったら閉じて消します。
    /// - Parameters:
    ///   - zip: ZIP のバイト列。
    ///   - body: 開いたファイルを使う処理。
    /// - Returns: 処理の結果。
    static func withFile<T>(_ zip: [UInt8], _ body: (FileHandle) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zip-test-\(UUID().uuidString).zip")
        try Data(zip).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try body(handle)
    }

    /// 責務: 中央ディレクトリを読みます。
    /// - Parameter zip: ZIP のバイト列。
    /// - Returns: エントリの一覧。
    static func entries(in zip: [UInt8]) throws -> [ZipArchiveEntry] {
        try withFile(zip) { try ZipCentralDirectoryReader().entries(in: $0) }
    }

    /// 責務: ファイル(フォルダでない)エントリを展開して連結します。名前を指定しなければ最初のファイルです。
    /// - Parameters:
    ///   - zip: ZIP のバイト列。
    ///   - name: 展開するエントリの名前。
    ///   - inflater: 使う展開器。
    /// - Returns: 展開結果。
    static func extractFile(
        _ zip: [UInt8], named name: String? = nil, inflater: ZipEntryInflater = ZipEntryInflater()
    ) throws -> Output {
        try withFile(zip) { handle in
            let entries = try ZipCentralDirectoryReader().entries(in: handle)
            let candidates = entries.filter { !$0.isDirectory && (name == nil || $0.path == name) }
            guard let entry = candidates.first else { throw SetupError.noFileEntry }
            return try stream(entry, from: handle, inflater: inflater)
        }
    }

    /// 責務: ZIP を読み、全ファイルを展開して、結果を分類します。
    /// - Parameters:
    ///   - zip: ZIP のバイト列。
    ///   - inflater: 使う展開器。
    /// - Returns: 成功か、最初に出たエラーの分類。
    static func outcome(of zip: [UInt8], inflater: ZipEntryInflater = ZipEntryInflater()) -> Outcome {
        do {
            try withFile(zip) { handle in
                for entry in try ZipCentralDirectoryReader().entries(in: handle) where !entry.isDirectory {
                    _ = try stream(entry, from: handle, inflater: inflater)
                }
            }
            return .succeeded
        } catch let error as ZipArchiveError {
            return .zipError(error)
        } catch {
            return .otherError(String(describing: error))
        }
    }

    /// 責務: 1エントリを展開し、出力と進捗と塊の大きさを集めます。
    private static func stream(_ entry: ZipArchiveEntry, from handle: FileHandle, inflater: ZipEntryInflater) throws -> Output {
        var output = Output()
        try inflater.stream(
            entry, from: handle,
            progress: { output.progress.append($0) },
            consume: { chunk in
                output.chunkSizes.append(chunk.count)
                output.bytes.append(contentsOf: chunk)
            }
        )
        return output
    }
}
