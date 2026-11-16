"""計測値を上限と比べて、超過した指標を取り出す。"""

from typing import List

from .limits import FILE_LIMITS, FUNCTION_LIMITS
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


def _file_findings(metrics: FileMetrics) -> List[Finding]:
    """責務: ファイル単位の超過を返す。行は 1。"""
    found = []
    for metric, limit in FILE_LIMITS.items():
        value = getattr(metrics, metric)
        if value > limit:
            found.append(Finding(metrics.path, 1, metric, value, limit))
    return found


def collect_findings(metrics: FileMetrics) -> List[Finding]:
    """責務: 1ファイルの計測値から上限超過をすべて集める。"""
    found = _file_findings(metrics)
    for func in metrics.functions:
        found.extend(_function_findings(metrics.path, func))
    return found
