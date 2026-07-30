"""ProjectZD8の制限付きPID式を副作用なく評価します。"""

from __future__ import annotations

import ast
import math
import re
from dataclasses import dataclass


class FormulaEvaluationError(ValueError):
    """PID式を安全に評価できない場合を表します。"""


class InsufficientBytesError(FormulaEvaluationError):
    """PID式に必要なpayload byteが不足した場合を表します。"""


class NonFiniteResultError(FormulaEvaluationError):
    """PID式の結果が有限値でない場合を表します。"""


ALLOWED_EXPRESSION = re.compile(r"[A-H0-9+\-*/().\s]+")


@dataclass(frozen=True)
class PIDDefinition:
    """匿名集計に必要なPID定義だけを保持します。"""

    service: int
    pid: int
    required_byte_count: int | None
    formula: str | None
    minimum_value: float | None
    maximum_value: float | None
    revision: int


def evaluate(definition: PIDDefinition, payload: bytes) -> float:
    """1件のPID定義をSwift実装と同じ演算子集合で評価します。"""

    if definition.required_byte_count is None or definition.formula is None:
        raise FormulaEvaluationError("formula unavailable")
    if len(payload) < definition.required_byte_count:
        raise InsufficientBytesError("payload is shorter than required byte count")
    if not ALLOWED_EXPRESSION.fullmatch(definition.formula):
        raise FormulaEvaluationError("expression contains an unsupported character")
    try:
        expression = ast.parse(definition.formula, mode="eval")
    except (SyntaxError, ValueError) as error:
        raise FormulaEvaluationError("invalid expression") from error
    variables = {chr(ord("A") + index): float(value) for index, value in enumerate(payload[:8])}
    try:
        result = _evaluate_node(expression.body, variables)
    except (ArithmeticError, OverflowError) as error:
        raise FormulaEvaluationError("arithmetic failure") from error
    if not math.isfinite(result):
        raise NonFiniteResultError("formula produced a non-finite value")
    return result


def classify(definition: PIDDefinition | None, payload: bytes) -> str:
    """1件のRaw応答を排他的な数値変換結果へ分類します。"""

    if definition is None:
        return "missingDefinition"
    if definition.required_byte_count is None or not definition.formula:
        return "unavailableFormula"
    if len(payload) < definition.required_byte_count:
        return "insufficientBytes"
    try:
        value = evaluate(definition, payload)
    except InsufficientBytesError:
        return "insufficientBytes"
    except NonFiniteResultError:
        return "nonFinite"
    except FormulaEvaluationError:
        return "invalidExpression"
    if definition.minimum_value is not None and value < definition.minimum_value:
        return "outOfDeclaredRange"
    if definition.maximum_value is not None and value > definition.maximum_value:
        return "outOfDeclaredRange"
    return "numericFinite"


def _evaluate_node(node: ast.AST, variables: dict[str, float]) -> float:
    """許可済みAST nodeだけを再帰評価します。"""

    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
        return float(node.value)
    if isinstance(node, ast.Name) and node.id in variables and len(node.id) == 1:
        return variables[node.id]
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        value = _evaluate_node(node.operand, variables)
        return value if isinstance(node.op, ast.UAdd) else -value
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
        left = _evaluate_node(node.left, variables)
        right = _evaluate_node(node.right, variables)
        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        if right == 0:
            raise FormulaEvaluationError("division by zero")
        return left / right
    raise FormulaEvaluationError("expression contains an unsupported token")
