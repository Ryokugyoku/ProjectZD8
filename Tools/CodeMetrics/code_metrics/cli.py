"""コマンドライン入口。モードの判別と、計測から出力までの流れをつなぐ。"""

import argparse
import os
import sys
from typing import List, Optional, TextIO

from .baseline import (
    BaselineError, build_baseline, judge, load_baseline, save_baseline,
)
from .findings import collect_findings
from .limits import BASELINE_RELATIVE_PATH
from .measure import LizardMissingError, measure_source
from .model import Finding, Judgement
from .report import format_report
from .selection import (
    GitError, changed_paths, filter_swift, find_root, hook_path, scan_all,
)

EXIT_OK = 0
EXIT_ERRORS = 1
EXIT_HOOK_ERRORS = 2
EXIT_LIZARD_MISSING = 3


def build_parser() -> argparse.ArgumentParser:
    """責務: コマンドライン引数の定義を作る。"""
    parser = argparse.ArgumentParser(description="Swift の複雑さチェック")
    parser.add_argument("files", nargs="*", metavar="FILE")
    parser.add_argument("--root")
    parser.add_argument("--changed-since", metavar="REF")
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--hook", action="store_true")
    return parser


def measure_findings(root: str, rel_paths: List[str]) -> List[Finding]:
    """責務: 指定ファイルを計測し、上限超過をすべて集める。"""
    found: List[Finding] = []
    for rel in rel_paths:
        full = os.path.join(root, rel)
        with open(full, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        found.extend(collect_findings(measure_source(rel, text)))
    return found


def _check(root: str, rel_paths: List[str]) -> List[Judgement]:
    """責務: ファイル群を計測してベースラインと照合した判定を返す。"""
    baseline = load_baseline(os.path.join(root, BASELINE_RELATIVE_PATH))
    return judge(measure_findings(root, rel_paths), baseline)


def _update_baseline(root: str) -> int:
    """責務: 全対象を計測して超過だけをベースラインへ書き出す。"""
    paths = filter_swift(scan_all(root), root, root)
    baseline = build_baseline(measure_findings(root, paths))
    save_baseline(os.path.join(root, BASELINE_RELATIVE_PATH), baseline)
    return EXIT_OK


def _select_paths(args, root: str, stdin: TextIO) -> List[str]:
    """責務: モードに応じて計測対象の相対パスを決める。"""
    if args.hook:
        path = hook_path(stdin.read())
        return filter_swift([path], root, root) if path else []
    if args.changed_since:
        return filter_swift(changed_paths(root, args.changed_since), root, root)
    return filter_swift(args.files, root, os.getcwd())


def _run(args, stdin: TextIO, stdout: TextIO, stderr: TextIO) -> int:
    """責務: 引数に従って実行し、終了コードを返す。"""
    root = os.path.realpath(args.root) if args.root else find_root(os.getcwd())
    if args.update_baseline:
        return _update_baseline(root)
    judgements = _check(root, _select_paths(args, root, stdin))
    lines = format_report(judgements, errors_only=args.hook)
    has_error = any(j.is_error for j in judgements)
    if args.hook:
        if has_error:
            stderr.write("\n".join(lines) + "\n")
        return EXIT_HOOK_ERRORS if has_error else EXIT_OK
    if lines:
        stdout.write("\n".join(lines) + "\n")
    return EXIT_ERRORS if has_error else EXIT_OK


def main(
    argv: Optional[List[str]] = None,
    stdin: Optional[TextIO] = None,
    stdout: Optional[TextIO] = None,
    stderr: Optional[TextIO] = None,
) -> int:
    """責務: 例外を終了コードへ変換しながら実行する。"""
    args = build_parser().parse_args(argv)
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    try:
        return _run(args, stdin, stdout, stderr)
    except LizardMissingError as error:
        stderr.write("lizard が見つかりません: {}\n".format(error))
        return EXIT_LIZARD_MISSING
    except (GitError, BaselineError) as error:
        stderr.write("{}\n".format(error))
        return EXIT_ERRORS
