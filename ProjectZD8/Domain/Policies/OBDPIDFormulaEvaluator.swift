import Foundation

/// 保存された制限付きPID数式を応答バイトへ適用します。
nonisolated struct OBDPIDFormulaEvaluator {
    /// PID定義の数式を指定バイト列で評価します。
    ///
    /// 責務: 1件の検証対象PID式を副作用なく有限数値へ変換します。
    /// - Parameters:
    ///   - definition: 評価する変換式と必要バイト数を持つPID定義。
    ///   - bytes: OBD応答からServiceとPIDを除いた未加工データバイト。
    /// - Returns: 定義式を適用した有限数値。
    /// - Throws: バイト不足、不正構文、未提供変数、ゼロ除算、非有限結果の場合は `OBDPIDFormulaError`。
    func evaluate(_ definition: OBDPIDDefinition, bytes: [UInt8]) throws -> Double {
        guard let requiredByteCount = definition.requiredByteCount,
              let formula = definition.formula else { throw OBDPIDFormulaError.invalidExpression }
        guard bytes.count >= requiredByteCount else {
            throw OBDPIDFormulaError.insufficientBytes(
                required: requiredByteCount,
                actual: bytes.count
            )
        }
        var parser = Parser(expression: formula, bytes: bytes)
        let value = try parser.parse()
        guard value.isFinite else { throw OBDPIDFormulaError.nonFiniteResult }
        return value
    }
}

/// PID式の許可済みトークンだけを再帰下降で評価します。
nonisolated private struct Parser {
    /// 評価対象の文字配列です。
    private let characters: [Character]
    /// `A`から`H`へ対応する応答バイトです。
    private let bytes: [UInt8]
    /// 次に解析する文字位置です。
    private var index = 0

    /// 数式文字列と応答バイトを使ってパーサーを生成します。
    ///
    /// 責務: 1件の式解析に必要な入力と読取位置を初期化します。
    /// - Parameters:
    ///   - expression: 解析対象の制限付き数式。
    ///   - bytes: 変数へ割り当てる応答バイト。
    init(expression: String, bytes: [UInt8]) {
        characters = Array(expression)
        self.bytes = bytes
    }

    /// 式全体を解析して末尾まで消費した値を返します。
    ///
    /// 責務: 1件の数式全体が許可済み構文だけで完結することを確認します。
    /// - Returns: 式全体の計算結果。
    /// - Throws: 構文または計算が不正な場合は `OBDPIDFormulaError`。
    mutating func parse() throws -> Double {
        let value = try parseExpression()
        skipWhitespace()
        guard index == characters.count else { throw OBDPIDFormulaError.invalidExpression }
        return value
    }

    /// 加算と減算を左結合で解析します。
    ///
    /// 責務: 乗除算項を加減算演算子で結合した値を返します。
    /// - Returns: 加減算式の値。
    /// - Throws: 子構文が不正な場合は `OBDPIDFormulaError`。
    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while let operation = consumeOne(of: ["+", "-"]) {
            let right = try parseTerm()
            value = operation == "+" ? value + right : value - right
        }
        return value
    }

    /// 乗算と除算を左結合で解析します。
    ///
    /// 責務: 単項値を乗除算演算子で結合した値を返します。
    /// - Returns: 乗除算式の値。
    /// - Throws: 子構文不正またはゼロ除算の場合は `OBDPIDFormulaError`。
    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()
        while let operation = consumeOne(of: ["*", "/"]) {
            let right = try parseUnary()
            if operation == "/", right == 0 { throw OBDPIDFormulaError.divisionByZero }
            value = operation == "*" ? value * right : value / right
        }
        return value
    }

    /// 任意個の単項符号を解析します。
    ///
    /// 責務: 1件の基本値へ先頭の正負符号を適用します。
    /// - Returns: 単項符号適用後の値。
    /// - Throws: 後続構文が不正な場合は `OBDPIDFormulaError`。
    private mutating func parseUnary() throws -> Double {
        if consume("+") { return try parseUnary() }
        if consume("-") { return -(try parseUnary()) }
        return try parsePrimary()
    }

    /// 数値、バイト変数、括弧式のいずれかを解析します。
    ///
    /// 責務: 1件の最小式要素を数値へ変換します。
    /// - Returns: 最小式要素の値。
    /// - Throws: 未提供変数または不正構文の場合は `OBDPIDFormulaError`。
    private mutating func parsePrimary() throws -> Double {
        skipWhitespace()
        if consume("(") {
            let value = try parseExpression()
            guard consume(")") else { throw OBDPIDFormulaError.invalidExpression }
            return value
        }
        if index < characters.count, let variableIndex = variableIndex(for: characters[index]) {
            let variable = characters[index]
            index += 1
            guard variableIndex < bytes.count else {
                throw OBDPIDFormulaError.unavailableVariable(variable)
            }
            return Double(bytes[variableIndex])
        }
        return try parseNumber()
    }

    /// 10進整数または小数を解析します。
    ///
    /// 責務: 連続する10進数字と小数点を1件の定数へ変換します。
    /// - Returns: 解析した10進定数。
    /// - Throws: 定数表現が不正な場合は `OBDPIDFormulaError.invalidExpression`。
    private mutating func parseNumber() throws -> Double {
        skipWhitespace()
        let start = index
        var decimalPointCount = 0
        while index < characters.count {
            let character = characters[index]
            if character == "." {
                decimalPointCount += 1
                if decimalPointCount > 1 { break }
                index += 1
            } else if character.isNumber {
                index += 1
            } else {
                break
            }
        }
        guard start < index, let value = Double(String(characters[start..<index])) else {
            throw OBDPIDFormulaError.invalidExpression
        }
        return value
    }

    /// 現在位置の文字が指定候補に一致すれば消費します。
    ///
    /// 責務: 1文字演算子候補から現在位置に一致する値を返します。
    /// - Parameter candidates: 許可する1文字演算子。
    /// - Returns: 消費した演算子。どれにも一致しない場合は `nil`。
    private mutating func consumeOne(of candidates: [Character]) -> Character? {
        skipWhitespace()
        guard index < characters.count, candidates.contains(characters[index]) else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    /// 現在位置の指定文字を一致時だけ消費します。
    ///
    /// 責務: 1件の期待文字を現在位置と照合して読取位置を進めます。
    /// - Parameter expected: 期待する1文字。
    /// - Returns: 一致して消費した場合は `true`。
    private mutating func consume(_ expected: Character) -> Bool {
        skipWhitespace()
        guard index < characters.count, characters[index] == expected else { return false }
        index += 1
        return true
    }

    /// 空白文字を読み飛ばします。
    ///
    /// 責務: 数式の意味に影響しない連続空白だけを現在位置から消費します。
    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    /// 許可済み変数を応答バイト位置へ変換します。
    ///
    /// 責務: `A`から`H`の1文字を0始まりバイト位置へ写像します。
    /// - Parameter character: 数式内の変数候補。
    /// - Returns: 許可済み変数の位置。それ以外は `nil`。
    private func variableIndex(for character: Character) -> Int? {
        guard let ascii = character.asciiValue, let a = Character("A").asciiValue,
              ascii >= a, ascii < a + 8 else { return nil }
        return Int(ascii - a)
    }
}
