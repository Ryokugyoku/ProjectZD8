import XCTest
@testable import ProjectZD8

/// analysis-expr.js の安全な式パーサーを検証します。
final class AnalysisExpressionTests: XCTestCase {
    private func evaluate(_ source: String, columns: String = "{}", n: Int = 1) throws -> [Double?] {
        try AnalysisWebScriptRunner.evaluate("""
            const p = parseExpression(\(jsString(source)));
            const cols = \(columns);
            return Array.from(evaluateExpression(p.ast, cols, \(n)), (v) => Number.isNaN(v) ? null : v);
        """, in: AnalysisWebScriptRunner.makeContext())
    }

    private func jsString(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(data: data, encoding: .utf8)!
    }

    /// 責務: 演算子の優先順位・結合性・単項・括弧・関数を確認します。
    func testArithmetic() throws {
        XCTAssertEqual(try evaluate("1 + 2 * 3"), [7])
        XCTAssertEqual(try evaluate("(1 + 2) * 3"), [9])
        XCTAssertEqual(try evaluate("2 ^ 3 ^ 2"), [512], "べき乗は右結合")
        XCTAssertEqual(try evaluate("-2 ^ 2"), [-4], "単項マイナスはべき乗より弱い")
        XCTAssertEqual(try evaluate("10 % 4 + abs(-3) + max(1, 5) + clamp(15, 0, 10)"), [2 + 3 + 5 + 10])
        XCTAssertEqual(try evaluate("if(3 > 2 && 1 < 2, 10, 20)"), [10])
        XCTAssertEqual(try evaluate("pi > 3 && e < 3"), [1])
        XCTAssertEqual(try evaluate("1e2 + .5"), [100.5])
    }

    /// 責務: ゼロ除算・不定な結果・欠測の入力は、NaN(欠測)として伝わることを確認します。
    func testUndefinedAndMissingPropagate() throws {
        XCTAssertEqual(try evaluate("1 / 0"), [nil])
        XCTAssertEqual(try evaluate("sqrt(-1)"), [nil])
        XCTAssertEqual(try evaluate("ln(0)"), [nil])
        let r = try evaluate("rpm * 2", columns: "{ 'alias:rpm': Float64Array.from([1, NaN, 3]) }", n: 3)
        XCTAssertEqual(r, [2, nil, 6])
    }

    /// 責務: チャンネル参照(別名・$PID・[名称])が集められることを確認します。
    func testReferences() throws {
        let refs: [String] = try AnalysisWebScriptRunner.evaluate("return parseExpression('rpm + $0D + [Engine speed] + rpm + $01-05').refs.map((r) => r.kind + ':' + r.value);", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(refs, ["alias:rpm", "pid:0D", "name:Engine speed", "pid:01-05"])
    }

    /// 責務: 文法外の入力を型付きの失敗にし、評価系の入口(eval・Function・プロパティ参照)を持たないことを確認します。
    func testRejectsUnsafeInput() throws {
        func code(_ source: String) throws -> String {
            try AnalysisWebScriptRunner.evaluate("try { parseExpression(\(jsString(source))); return 'ok'; } catch (e) { return e.code; }", in: AnalysisWebScriptRunner.makeContext())
        }
        XCTAssertEqual(try code("eval(1)"), "unknownFunction")
        XCTAssertEqual(try code("constructor(1)"), "unknownFunction", "プロトタイプ上の名前は関数として使えない")
        XCTAssertEqual(try code("toString(1)"), "unknownFunction")
        XCTAssertEqual(try code("a.b"), "unexpectedChar", "プロパティ参照は文法に無い")
        XCTAssertEqual(try code("a[0]"), "unexpectedToken", "[...]はチャンネル名の参照であり、添字ではない")
        XCTAssertEqual(try code("1 +"), "unexpectedToken")
        XCTAssertEqual(try code("(1"), "unexpectedToken")
        XCTAssertEqual(try code("max(1)"), "badArguments")
        XCTAssertEqual(try code(""), "empty")
        XCTAssertEqual(try code("'x'"), "unexpectedChar")
        XCTAssertEqual(try code(String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)), "tooDeep")
        XCTAssertEqual(try code(String(repeating: "1+", count: 400) + "1"), "tooLong")
        let source = try AnalysisWebScriptRunner.source(named: "analysis-expr")
        XCTAssertFalse(source.contains("eval("))
        XCTAssertFalse(source.contains("new Function"))
    }

    /// 責務: 全ての配信スクリプトが `eval` と `Function` コンストラクタを使っていないことを確認します。
    func testNoDynamicCodeExecutionAnywhere() throws {
        for name in AnalysisWebFiles.scripts {
            let source = try AnalysisWebScriptRunner.source(named: name)
            XCTAssertNil(source.range(of: #"\beval\s*\("#, options: .regularExpression), name)
            XCTAssertNil(source.range(of: #"new\s+Function\b"#, options: .regularExpression), name)
            XCTAssertNil(source.range(of: #"\bFunction\s*\("#, options: .regularExpression), name)
            XCTAssertNil(source.range(of: #"setTimeout\s*\(\s*['"`]"#, options: .regularExpression), name)
            XCTAssertNil(source.range(of: #"https?://"#, options: .regularExpression), "\(name): 外部URLを参照しない")
        }
    }
}
