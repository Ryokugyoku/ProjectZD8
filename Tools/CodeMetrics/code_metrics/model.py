"""計測結果と違反を表すデータ型。"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class FunctionMetrics:
    """1関数の計測値。occurrence は同名関数の出現順(0 始まり)。"""

    name: str
    occurrence: int
    start_line: int
    end_line: int
    cyclomatic: int
    cognitive: int
    nesting: int
    function_length: int


@dataclass
class FileMetrics:
    """1ファイルの計測値。"""

    path: str
    file_lines: int
    function_count: int
    functions: List[FunctionMetrics] = field(default_factory=list)
    long_line_numbers: Tuple[int, ...] = ()

    @property
    def long_lines(self) -> int:
        """責務: 160文字を超える行の数を返す。"""
        return len(self.long_line_numbers)


@dataclass(frozen=True)
class Finding:
    """上限を超えた1件。function が None ならファイル単位の指標。"""

    path: str
    line: int
    metric: str
    value: int
    limit: int
    function: Optional[str] = None
    occurrence: int = 0
    line_numbers: Tuple[int, ...] = ()


@dataclass(frozen=True)
class Judgement:
    """違反の判定結果。baseline はベースラインで許容した記録値(なければ None)。"""

    finding: Finding
    baseline: Optional[int] = None

    @property
    def is_error(self) -> bool:
        """責務: ベースラインで許容されていない(エラー扱いの)違反かを返す。"""
        return self.baseline is None
