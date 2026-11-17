"""コマンドライン引数を解釈し、実行の指定(`RunOptions`)へまとめる。"""

import argparse
import re
from dataclasses import dataclass
from typing import List, Pattern, Sequence, Tuple

COMMAND_SEPARATOR = "--"
DEFAULT_LOCK_WAIT_SECONDS = 3600
_DIGITS = re.compile(r"\d+", re.ASCII)


class UsageError(Exception):
    """引数や設定値が不正なことを表す例外(終了コード 2 に対応する)。"""


@dataclass(frozen=True)
class RunOptions:
    """1回の実行の指定。上限の秒数、照合する正規表現、実行するコマンドを持つ。"""

    limit_seconds: int
    lock_wait_seconds: int
    kill_patterns: List[Pattern[str]]
    command: List[str]


class _RaisingParser(argparse.ArgumentParser):
    """エラー時に終了せず `UsageError` を投げる引数パーサー。"""

    def error(self, message: str) -> None:  # type: ignore[override]
        """責務: argparse の引数エラーを `UsageError` に変換して呼び出し側へ返す。"""
        raise UsageError(message)


def _parse_int(text: str, minimum: int) -> int:
    """責務: 10進数字だけの文字列を整数にし、下限未満なら型エラーにする。"""
    if not _DIGITS.fullmatch(text):
        raise argparse.ArgumentTypeError("整数ではありません: {!r}".format(text))
    value = int(text)
    if value < minimum:
        raise argparse.ArgumentTypeError("{} 以上の整数が必要です: {}".format(minimum, value))
    return value


def _limit_seconds(text: str) -> int:
    """責務: `--limit` の値を 1 以上の整数として解釈する。"""
    return _parse_int(text, 1)


def _lock_wait_seconds(text: str) -> int:
    """責務: `--lock-wait` の値を 0 以上の整数として解釈する。"""
    return _parse_int(text, 0)


def _kill_pattern(text: str) -> Pattern[str]:
    """責務: `--kill-pattern` の値を正規表現としてコンパイルし、不正なら型エラーにする。"""
    try:
        return re.compile(text)
    except re.error as error:
        raise argparse.ArgumentTypeError("正規表現が不正です: {!r} ({})".format(text, error))


def build_parser() -> argparse.ArgumentParser:
    """責務: `--` より前のオプションの定義を作る。"""
    parser = _RaisingParser(
        prog="run_xcodebuild.py",
        description="xcodebuild を直列・時間上限つきで実行する",
        allow_abbrev=False,
    )
    parser.add_argument("--limit", type=_limit_seconds, required=True, metavar="SECONDS")
    parser.add_argument(
        "--lock-wait", type=_lock_wait_seconds, default=DEFAULT_LOCK_WAIT_SECONDS, metavar="SECONDS",
    )
    parser.add_argument("--kill-pattern", type=_kill_pattern, action="append", default=[], metavar="REGEX")
    return parser


def split_command(argv: Sequence[str]) -> Tuple[List[str], List[str]]:
    """責務: 引数列を最初の `--` で、オプション部分と実行するコマンドに分ける。"""
    arguments = list(argv)
    if COMMAND_SEPARATOR not in arguments:
        raise UsageError("`--` の後ろに実行するコマンドが必要です")
    index = arguments.index(COMMAND_SEPARATOR)
    command = arguments[index + 1:]
    if not command:
        raise UsageError("`--` の後ろのコマンドが空です")
    return arguments[:index], command


def parse_arguments(argv: Sequence[str]) -> RunOptions:
    """責務: 引数列全体を検証し、`RunOptions` を返す。不正なら `UsageError` を投げる。"""
    option_part, command = split_command(argv)
    namespace = build_parser().parse_args(option_part)
    return RunOptions(
        limit_seconds=namespace.limit,
        lock_wait_seconds=namespace.lock_wait,
        kill_patterns=list(namespace.kill_pattern),
        command=command,
    )
