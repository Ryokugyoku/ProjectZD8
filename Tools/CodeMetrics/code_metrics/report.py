"""判定結果を `パス:行: error|warning: ...` 形式の行にする。"""

from typing import List

from .model import Judgement

_MAX_SHOWN_LINES = 5


def _format_line_numbers(numbers) -> str:
    """責務: 超過行の番号を `lines 12, 40` 形式にする(最大5件、超えたら `, ...`)。"""
    shown = ", ".join(str(n) for n in numbers[:_MAX_SHOWN_LINES])
    suffix = ", ..." if len(numbers) > _MAX_SHOWN_LINES else ""
    return "lines " + shown + suffix


def format_judgement(judgement: Judgement) -> str:
    """責務: 判定1件を出力1行にする。"""
    f = judgement.finding
    severity = "error" if judgement.is_error else "warning"
    line = "{}:{}: {}: {} {} > {}".format(
        f.path, f.line, severity, f.metric, f.value, f.limit
    )
    if f.line_numbers:
        line += " ({})".format(_format_line_numbers(f.line_numbers))
    if f.function is not None:
        line += " ({})".format(f.function)
    if judgement.baseline is not None:
        line += " [baseline {}]".format(judgement.baseline)
    return line


def sort_judgements(judgements: List[Judgement]) -> List[Judgement]:
    """責務: パス順、同パスは行順、同じ行は指標 ID 順に並べる。"""
    return sorted(
        judgements,
        key=lambda j: (j.finding.path, j.finding.line, j.finding.metric),
    )


def format_report(judgements: List[Judgement], errors_only: bool) -> List[str]:
    """責務: 並べ替えた出力行を返す。errors_only なら警告を除く。"""
    ordered = sort_judgements(judgements)
    return [
        format_judgement(j) for j in ordered if j.is_error or not errors_only
    ]
