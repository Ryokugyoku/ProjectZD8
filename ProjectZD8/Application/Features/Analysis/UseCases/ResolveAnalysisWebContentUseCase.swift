import Foundation

/// スキームハンドラが返す1件の内容です。
nonisolated struct AnalysisWebContent: Equatable, Sendable {
    let data: Data
    let mimeType: String
}

/// ワークベンチの要求パスを、同梱ファイルまたは分析データへ解決します。
///
/// `file://` を使わず、許可したファイル名と保存済みデータだけを返します。
nonisolated struct ResolveAnalysisWebContentUseCase: Sendable {
    /// ワークベンチを配信するURLスキームです。
    static let scheme = "rtanalysis"
    /// ワークベンチのホスト名です。
    static let host = "app"
    /// 入口のHTMLファイル名です。
    static let indexFilename = "analysis-index.html"

    private let resourceDirectory: URL
    private let store: AnalysisDatasetStore

    /// ユースケースを生成します。
    ///
    /// 責務: 同梱リソースの場所と分析データの置き場を固定します。
    init(resourceDirectory: URL, store: AnalysisDatasetStore) {
        self.resourceDirectory = resourceDirectory
        self.store = store
    }

    /// 入口ページのURLです。
    static var indexURL: URL { indexURL(trailingInset: 0) }

    /// 責務: 入口ページのURLを作ります。ホスト側が重ねる操作部品のために、上部バー右端へ空ける幅(CSSピクセル)を渡せます。
    static func indexURL(trailingInset: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(indexFilename)"
        if trailingInset > 0 { components.queryItems = [URLQueryItem(name: "trailingInset", value: String(trailingInset))] }
        return components.url!
    }

    /// 要求URLを内容へ解決します。
    ///
    /// 責務: 許可したパスだけを同梱ファイルまたは保存済みデータとして返し、それ以外は拒否します。
    /// - Returns: 内容。許可外や存在しないパスは `nil`。
    func content(for url: URL) -> AnalysisWebContent? {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = Self.indexFilename }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.count == 2, components[0] == "dataset" || components[0] == "trend" {
            guard Self.isSafeName(components[1]), components[1].hasSuffix(".json"),
                  let data = store.data(forPath: path) else { return nil }
            return AnalysisWebContent(data: data, mimeType: "application/json")
        }
        guard components.count == 1, Self.isSafeName(path), let mimeType = Self.mimeType(for: path) else { return nil }
        guard let data = try? Data(contentsOf: resourceDirectory.appendingPathComponent(path)) else { return nil }
        return AnalysisWebContent(data: data, mimeType: mimeType)
    }

    /// 責務: 英数字・ハイフン・ピリオドだけで構成され、`..` を含まない名前か確認します。
    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && !name.hasPrefix(".")
            && name.unicodeScalars.allSatisfy { ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)))) || $0 == "-" || $0 == "." }
    }

    /// 責務: 配信を許可する拡張子のMIMEタイプを返します。
    private static func mimeType(for name: String) -> String? {
        switch (name as NSString).pathExtension {
        case "html": "text/html"
        case "js": "text/javascript"
        case "css": "text/css"
        case "svg": "image/svg+xml"
        default: nil
        }
    }
}
