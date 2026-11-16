"""ファイル内の「関数の数」を数える(宣言行のキーワードで判定)。"""

from typing import Dict, List, Set

from .model import FunctionMetrics

_KEYWORDS = frozenset({"func", "init", "subscript", "deinit"})


def _is_nested(func: FunctionMetrics, others: List[FunctionMetrics]) -> bool:
    """責務: func が他の関数の本体に含まれるかを返す。"""
    for other in others:
        if other is func:
            continue
        inside = other.start_line <= func.start_line
        inside = inside and func.end_line <= other.end_line
        same = (other.start_line, other.end_line) == (
            func.start_line,
            func.end_line,
        )
        if inside and not same:
            return True
    return False


def count_functions(
    functions: List[FunctionMetrics], words_by_line: Dict[int, Set[str]]
) -> int:
    """責務: 宣言行に func/init/subscript/deinit を持つ非ネスト関数の数を返す。"""
    total = 0
    for func in functions:
        words = words_by_line.get(func.start_line, set())
        if words & _KEYWORDS and not _is_nested(func, functions):
            total += 1
    return total
