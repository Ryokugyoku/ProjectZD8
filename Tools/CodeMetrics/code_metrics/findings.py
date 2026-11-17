"""計測値を上限と比べて、超過した指標を取り出す。"""

from typing import List

from .limits import FILE_LIMITS, FUNCTION_LIMITS, LONG_LINES
from .model import FileMetrics, Finding, FunctionMetrics


def _function_findings(path: str, func: FunctionMetrics) -> List[Finding]:
    """責務: 1関数の超過(上限と等しいものは除く)を返す。"""
    found = []
    for metric, limit in FUNCTION_LIMITS.items():
        value = getattr(func, metric)
        if value > limit:
            found.append(
                Finding(
                    path, func.start_line, metric, value, limit,
                    func.name, func.occurrence,
                )
            )
    return found


def _file_finding(
    metrics: FileMetrics, metric: str, value: int, limit: int
) -> Finding:
    """責務: ファイル単位の超過1件を作る。long_lines は最初の超過行と行番号を持つ。"""
    if metric == LONG_LINES:
        numbers = metrics.long_line_numbers
        return Finding(
            metrics.path, numbers[0], metric, value, limit,
            line_numbers=numbers,
        )
    return Finding(metrics.path, 1, metric, value, limit)


def _file_findings(metrics: FileMetrics) -> List[Finding]:
    """責務: ファイル単位の超過を返す。行は 1(long_lines だけは最初の超過行)。"""
    found = []
    for metric, limit in FILE_LIMITS.items():
        value = getattr(metrics, metric)
        if value > limit:
            found.append(_file_finding(metrics, metric, value, limit))
    return found


def collect_findings(metrics: FileMetrics) -> List[Finding]:
    """責務: 1ファイルの計測値から上限超過をすべて集める。"""
    found = _file_findings(metrics)
    for func in metrics.functions:
        found.extend(_function_findings(metrics.path, func))
    return found
