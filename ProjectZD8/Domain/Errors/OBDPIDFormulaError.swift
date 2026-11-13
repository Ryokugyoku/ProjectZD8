/// PID変換式を安全に評価できなかった理由です。
enum OBDPIDFormulaError: Error, Equatable {
    /// 定義が要求する応答バイト数を満たしていません。
    case insufficientBytes(required: Int, actual: Int)
    /// 数式に許可されていない文字または構文があります。
    case invalidExpression
    /// 数式が実データに存在しないバイト変数を参照しています。
    case unavailableVariable(Character)
    /// ゼロ除算が発生しました。
    case divisionByZero
    /// 計算結果が有限値になりませんでした。
    case nonFiniteResult
}
