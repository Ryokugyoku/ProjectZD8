"""制限付きPID式と排他的変換分類を検証します。"""

import unittest

from formula_evaluator import FormulaEvaluationError, PIDDefinition, classify, evaluate


class FormulaEvaluatorTests(unittest.TestCase):
    """Swift側の許可演算子とデータ品質分類の一致を検証します。"""

    def definition(self, **changes: object) -> PIDDefinition:
        """テスト用PID定義へ指定差分を適用します。"""

        values = {
            "service": 1,
            "pid": 12,
            "required_byte_count": 2,
            "formula": "(A * 256 + B) / 4",
            "minimum_value": 0.0,
            "maximum_value": 16_383.75,
            "revision": 2,
        }
        values.update(changes)
        return PIDDefinition(**values)

    def test_evaluates_supported_arithmetic(self) -> None:
        """A-H変数と四則演算を有限値へ変換します。"""

        self.assertEqual(evaluate(self.definition(), bytes([0x1A, 0xF8])), 1726.0)

    def test_rejects_unsupported_expression(self) -> None:
        """関数呼出しを許可構文として評価しません。"""

        with self.assertRaises(FormulaEvaluationError):
            evaluate(self.definition(formula="sqrt(A)"), bytes([4, 0]))

    def test_classifies_all_exclusive_outcomes(self) -> None:
        """7種類の変換結果を重複なく分類します。"""

        self.assertEqual(classify(None, b"\x00"), "missingDefinition")
        self.assertEqual(classify(self.definition(required_byte_count=None, formula=None), b""), "unavailableFormula")
        self.assertEqual(classify(self.definition(), b"\x01"), "insufficientBytes")
        self.assertEqual(classify(self.definition(formula="A ** 2"), b"\x01\x00"), "invalidExpression")
        self.assertEqual(classify(self.definition(formula="1 / (A - A)"), b"\x01\x00"), "invalidExpression")
        self.assertEqual(classify(self.definition(formula="1e2"), b"\x01\x00"), "invalidExpression")
        self.assertEqual(classify(self.definition(formula="A", maximum_value=10), b"\x0b\x00"), "outOfDeclaredRange")
        self.assertEqual(classify(self.definition(), b"\x01\x00"), "numericFinite")


if __name__ == "__main__":
    unittest.main()
