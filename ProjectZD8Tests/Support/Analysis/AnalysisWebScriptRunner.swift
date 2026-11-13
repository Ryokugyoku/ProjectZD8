import JavaScriptCore
import XCTest
@testable import ProjectZD8

/// 同梱したWebワークベンチのスクリプトをJavaScriptCoreで評価するテスト補助です。
///
/// ESモジュールの `import` / `export` を取り除いて、指定モジュールを1つのスコープへ連結して実行します。
/// 純粋な数値モジュール(DOMに触れないもの)だけを対象にします。
nonisolated enum AnalysisWebScriptRunner {
    /// DOMに触れない純粋モジュールを、依存の先から順に並べたものです。
    static let pureModules = [
        "analysis-stats", "analysis-decimate", "analysis-join", "analysis-binning", "analysis-segment",
        "analysis-expr", "analysis-derive", "analysis-csv", "analysis-i18n", "analysis-demo", "analysis-model"
    ]

    /// 責務: アプリバンドルからWebリソースのテキストを読みます。
    static func source(named name: String, extension ext: String = "js") throws -> String {
        let bundle = Bundle(for: AnalysisDatasetStore.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "AnalysisWebScriptRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing resource \(name).\(ext)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 責務: `import` 文を除き、`export` 修飾子を外した、連結可能なスクリプトにします。
    static func flatten(_ source: String) -> String {
        var text = source
        text = text.replacingOccurrences(of: #"(?m)^import\s[^;]*;\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^export\s+(?=function|const|class|let|async)"#, with: "", options: .regularExpression)
        return text
    }

    /// 責務: 純粋モジュールを読み込んだ評価環境を作ります。
    static func makeContext(modules: [String] = pureModules) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        let bundled = try modules.map { try flatten(source(named: $0)) }.joined(separator: "\n")
        context.evaluateScript(bundled)
        if let failure { throw NSError(domain: "AnalysisWebScriptRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: failure]) }
        return context
    }

    /// 責務: スクリプトを評価し、結果をJSON文字列経由で型付きの値へ変換します。
    static func evaluate<Value: Decodable>(_ script: String, in context: JSContext, as type: Value.Type = Value.self) throws -> Value {
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        let wrapped = "JSON.stringify((function(){ \(script) })())"
        let result = context.evaluateScript(wrapped)
        if let failure { throw NSError(domain: "AnalysisWebScriptRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: failure]) }
        guard let json = result?.toString(), json != "undefined" else {
            throw NSError(domain: "AnalysisWebScriptRunner", code: 4, userInfo: [NSLocalizedDescriptionKey: "No result"])
        }
        return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }
}
