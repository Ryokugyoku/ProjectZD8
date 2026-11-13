import XCTest
@testable import ProjectZD8

/// PID定義式の構文、バイト境界、算術失敗を検証します。
final class OBDPIDFormulaEvaluatorTests: XCTestCase {
    /// 冷却水温の1バイトoffset式を評価します。
    ///
    /// 責務: `A - 40` が一次資料の例と同じ83度を返すことを確認します。
    func testEvaluatesCoolantTemperatureFormula() throws {
        XCTAssertEqual(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 1, formula: "A - 40"), bytes: [0x7B]), 83)
    }

    /// 回転数の2バイト式と演算優先順位を評価します。
    ///
    /// 責務: 括弧、乗算、加算、除算が1726 rpmへ評価されることを確認します。
    func testEvaluatesEngineSpeedFormula() throws {
        XCTAssertEqual(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 2, formula: "(A * 256 + B) / 4"), bytes: [0x1A, 0xF8]), 1726)
    }

    /// 必要バイト数未満の応答を拒否します。
    ///
    /// 責務: 2バイト定義へ1バイトだけ渡した失敗理由を確認します。
    func testRejectsInsufficientBytes() {
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 2, formula: "A + B"), bytes: [1])) {
            XCTAssertEqual($0 as? OBDPIDFormulaError, .insufficientBytes(required: 2, actual: 1))
        }
    }

    /// 存在しない変数参照を拒否します。
    ///
    /// 責務: 1バイト応答に対するB参照が明示的な変数不足になることを確認します。
    func testRejectsUnavailableVariable() {
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 1, formula: "B"), bytes: [1])) {
            XCTAssertEqual($0 as? OBDPIDFormulaError, .unavailableVariable("B"))
        }
    }

    /// ゼロ除算を拒否します。
    ///
    /// 責務: 実データにより分母がゼロになる式を有限値へ変換しないことを確認します。
    func testRejectsDivisionByZero() {
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 1, formula: "1 / A"), bytes: [0])) {
            XCTAssertEqual($0 as? OBDPIDFormulaError, .divisionByZero)
        }
    }

    /// 任意関数や識別子を許可しません。
    ///
    /// 責務: 制限外の文字列がコードまたは関数として実行されないことを確認します。
    func testRejectsUnsupportedSyntax() {
        XCTAssertThrowsError(try OBDPIDFormulaEvaluator().evaluate(makeDefinition(bytes: 1, formula: "sqrt(A)"), bytes: [4])) {
            XCTAssertEqual($0 as? OBDPIDFormulaError, .invalidExpression)
        }
    }

    /// テスト対象の式だけを差し替えた定義を生成します。
    ///
    /// 責務: PID式テストへ必要な最小定義を決定的に提供します。
    /// - Parameters:
    ///   - bytes: 必要バイト数。
    ///   - formula: 評価対象式。
    /// - Returns: Service 01 PID 05相当のテスト定義。
    private func makeDefinition(bytes: Int, formula: String) -> OBDPIDDefinition {
        OBDPIDDefinition(service: 1, pid: 5, nameKey: "test", requiredByteCount: bytes, formula: formula, unit: "u", minimumValue: nil, maximumValue: nil, sourceURI: "test://source", revision: 1)
    }
}
