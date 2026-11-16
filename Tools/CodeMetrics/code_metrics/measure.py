"""lizard と独自の計測を合わせて、1ファイルの計測値を作る。"""

from collections import defaultdict
from typing import Dict, List

from .function_count import count_functions
from .model import FileMetrics, FunctionMetrics
from .nesting import function_nesting
from .tokenizer import TokenStream, tokenize


class LizardMissingError(Exception):
    """lizard が import できないことを表す。"""


def count_lines(text: str) -> int:
    """責務: 物理行数(改行の数。末尾に改行がない最終行も1行)を返す。"""
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def _analyze(path: str, text: str) -> list:
    """責務: lizard(認知的複雑度の拡張つき)で関数一覧を得る。"""
    try:
        import lizard
    except ImportError as error:
        raise LizardMissingError(str(error)) from error
    analyzer = lizard.FileAnalyzer(lizard.get_extensions(["cognitive"]))
    return analyzer.analyze_source_code(path, text).function_list


def _build_function(raw, occurrence: int, stream: TokenStream) -> FunctionMetrics:
    """責務: lizard の関数情報とネスト計測から FunctionMetrics を作る。"""
    return FunctionMetrics(
        name=raw.name,
        occurrence=occurrence,
        start_line=raw.start_line,
        end_line=raw.end_line,
        cyclomatic=raw.cyclomatic_complexity,
        cognitive=getattr(raw, "cognitive_complexity", 0),
        nesting=function_nesting(
            stream, raw.name, raw.start_line, raw.end_line
        ),
        function_length=raw.end_line - raw.start_line + 1,
    )


def _build_functions(raws: list, stream: TokenStream) -> List[FunctionMetrics]:
    """責務: 出現順(開始行順)に同名の通し番号を振って関数計測値を作る。"""
    ordered = sorted(raws, key=lambda r: (r.start_line, -r.end_line))
    seen: Dict[str, int] = defaultdict(int)
    result = []
    for raw in ordered:
        result.append(_build_function(raw, seen[raw.name], stream))
        seen[raw.name] += 1
    return result


def measure_source(path: str, text: str) -> FileMetrics:
    """責務: Swift ソース1本の全指標を計測する。"""
    stream = tokenize(text)
    functions = _build_functions(_analyze(path, text), stream)
    return FileMetrics(
        path=path,
        file_lines=count_lines(text),
        function_count=count_functions(functions, stream.words_by_line()),
        functions=functions,
    )
