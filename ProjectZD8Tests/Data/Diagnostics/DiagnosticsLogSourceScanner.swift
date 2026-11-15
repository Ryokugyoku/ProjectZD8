import Foundation

/// 製品ソースを走査し、`Logger(`・`OSSignposter(`・`OSLog(` の生成箇所とその引数を取り出すテスト部品です。
///
/// 行頭が `//` のコメント行は走査から外します。引数は対応する閉じ括弧まで(複数行にまたがっても)読みます。
/// ファイル列挙とテキスト走査はどちらも件数・長さの上限を持ち、上限を超えたら打ち切らずにエラーにします。
struct DiagnosticsLogSourceScanner {
    /// 1回の列挙で許すファイル数の上限です。超えたら走査の不具合とみなします。
    static let maximumFileCount = 10_000

    /// 生成箇所1件です。
    struct CreationSite {
        /// リポジトリルートからの相対パス。
        let path: String
        /// 1始まりの行番号。
        let line: Int
        /// 括弧の中の引数の文字列。
        let arguments: String

        /// `subsystem:` に渡した式です。無ければ `nil`。
        var subsystem: String? {
            DiagnosticsLogSourceScanner.firstCapture(#"subsystem:\s*([^,\)]+?)\s*(?:,|$)"#, in: arguments)
        }

        /// `category:` に渡した文字列リテラルの中身です。無ければ `nil`。
        var category: String? {
            DiagnosticsLogSourceScanner.firstCapture(#"category:\s*"([^"]*)""#, in: arguments)
        }
    }

    /// 走査のエラーです。
    enum ScanError: Error {
        /// テストファイル位置からリポジトリルートを特定できませんでした。
        case repositoryRootNotFound
        /// ファイル数が上限を超えました。
        case tooManyFiles(String)
        /// 生成箇所の閉じ括弧が見つかりませんでした。
        case unterminatedCall(String, Int)
    }

    /// リポジトリルートのURLです。
    let repositoryRoot: URL

    /// テストファイル位置からリポジトリルートを解決して生成します。
    ///
    /// 責務: `ProjectZD8Tests` の親ディレクトリを走査の起点にします。
    /// - Parameter testFilePath: 呼び出し元のテストファイルのパス。
    /// - Throws: `ProjectZD8Tests` を特定できない場合の `ScanError.repositoryRootNotFound`。
    init(testFilePath: String = #filePath) throws {
        let components = URL(filePath: testFilePath).pathComponents
        guard let testsIndex = components.firstIndex(of: "ProjectZD8Tests") else { throw ScanError.repositoryRootNotFound }
        repositoryRoot = URL(filePath: NSString.path(withComponents: Array(components[..<testsIndex])))
    }

    /// 指定ディレクトリ配下の Swift ソースを、上限付きで列挙します。
    ///
    /// 責務: `FileManager` の列挙(再帰呼び出しなし)で `.swift` を集め、上限を超えたらエラーにします。
    /// - Parameter relativeDirectory: リポジトリルートからの相対ディレクトリ。
    /// - Returns: 相対パスと内容の組。
    /// - Throws: 上限超過、または読込の失敗。
    func swiftSources(under relativeDirectory: String) throws -> [(path: String, text: String)] {
        let directory = repositoryRoot.appending(path: relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var rootPath = repositoryRoot.path(percentEncoded: false)
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        var sources: [(path: String, text: String)] = []
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > Self.maximumFileCount { throw ScanError.tooManyFiles(relativeDirectory) }
            guard url.pathExtension == "swift" else { continue }
            let absolutePath = url.path(percentEncoded: false)
            let path = absolutePath.hasPrefix(rootPath) ? String(absolutePath.dropFirst(rootPath.count)) : absolutePath
            sources.append((path, try String(contentsOf: url, encoding: .utf8)))
        }
        return sources
    }

    /// 指定ディレクトリ配下の生成箇所をすべて返します。
    ///
    /// 責務: コメント行を除いた各ソースから、生成箇所の行番号と引数を取り出します。
    /// - Parameter relativeDirectory: リポジトリルートからの相対ディレクトリ。
    /// - Returns: 生成箇所。
    /// - Throws: 列挙・読込の失敗、または閉じ括弧が見つからない場合のエラー。
    func creationSites(under relativeDirectory: String) throws -> [CreationSite] {
        let pattern = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])(Logger|OSSignposter|OSLog)\("#)
        return try swiftSources(under: relativeDirectory).flatMap { source -> [CreationSite] in
            let code = Self.removingCommentLines(source.text) as NSString
            return try pattern.matches(in: code as String, range: NSRange(location: 0, length: code.length)).map { match in
                let open = match.range.location + match.range.length
                let line = code.substring(to: match.range.location).components(separatedBy: "\n").count
                guard let arguments = Self.arguments(from: open, in: code) else {
                    throw ScanError.unterminatedCall(source.path, line)
                }
                return CreationSite(path: source.path, line: line, arguments: arguments)
            }
        }
    }

    /// 行頭が `//` の行を空行に置き換えます(行番号は保ちます)。
    ///
    /// 責務: DocC とコメント中の型名を生成箇所と誤認しないようにします。
    /// - Parameter text: ソース全体。
    /// - Returns: コメント行を空にしたソース。
    static func removingCommentLines(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 }
            .joined(separator: "\n")
    }

    /// 開き括弧の直後から、対応する閉じ括弧の手前までを返します。
    ///
    /// 責務: 文字列リテラル内の括弧を数えずに深さを追い、ソースの末尾までで打ち切ります。
    /// - Parameters:
    ///   - start: 開き括弧の直後の位置(UTF-16)。
    ///   - code: ソース全体。
    /// - Returns: 引数の文字列。閉じ括弧が無ければ `nil`。
    static func arguments(from start: Int, in code: NSString) -> String? {
        var depth = 1
        var inString = false
        var index = start
        while index < code.length {
            let character = code.character(at: index)
            if character == 0x22, index == 0 || code.character(at: index - 1) != 0x5C { inString.toggle() }
            if !inString, character == 0x28 { depth += 1 }
            if !inString, character == 0x29 {
                depth -= 1
                if depth == 0 { return code.substring(with: NSRange(location: start, length: index - start)) }
            }
            index += 1
        }
        return nil
    }

    /// 正規表現の最初の一致の第1キャプチャを返します。
    ///
    /// 責務: 引数の文字列から1つの値を取り出します。
    /// - Parameters:
    ///   - pattern: 第1キャプチャを持つ正規表現。
    ///   - text: 検索対象。
    /// - Returns: 前後の空白を除いたキャプチャ。一致しなければ `nil`。
    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return text[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
