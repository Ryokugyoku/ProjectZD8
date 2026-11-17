"""コマンドを新しいプロセスグループで起動し、時間上限まで終了を待つ。上限超過・中断時に止める。"""

import subprocess
from typing import List, Optional, Pattern, Sequence

from .diagnostics import report_note
from .process_stopper import stop_pids, stop_process_group
from .process_table import ProcessTableError, find_matching_pids

SIGNAL_EXIT_BASE = 128


class CommandLaunchError(Exception):
    """コマンドが見つからない・実行できないことを表す例外(終了コード 127 に対応する)。"""


def exit_code_from_returncode(returncode: int) -> int:
    """責務: Popen の終了コードを返す値へ直す。シグナルで終わった場合は 128 + 番号にする。"""
    if returncode < 0:
        return SIGNAL_EXIT_BASE - returncode
    return returncode


def start_command(command: Sequence[str]) -> "subprocess.Popen[bytes]":
    """責務: シェルを通さず、新しいセッション(プロセスグループ)でコマンドを起動する。"""
    try:
        return subprocess.Popen(list(command), start_new_session=True)
    except OSError as error:
        raise CommandLaunchError("コマンドを実行できません: {!r} ({})".format(command[0], error))


def wait_with_limit(process: "subprocess.Popen[bytes]", limit_seconds: float) -> Optional[int]:
    """責務: 上限の秒数までコマンドの終了を待ち、終了コードを返す。上限を過ぎたら None を返す。"""
    try:
        returncode = process.wait(timeout=limit_seconds)
    except subprocess.TimeoutExpired:
        return None
    return exit_code_from_returncode(returncode)


def stop_matching_processes(patterns: List[Pattern[str]], grace_seconds: float) -> None:
    """責務: `--kill-pattern` に一致するプロセス(自分と祖先を除く)を止める。"""
    if not patterns:
        return
    try:
        pids = find_matching_pids(patterns)
    except ProcessTableError as error:
        report_note("--kill-pattern の照合をできませんでした: {}".format(error))
        return
    if pids:
        report_note("--kill-pattern に一致したプロセスを止めます: {}".format(", ".join(str(pid) for pid in pids)))
    stop_pids(pids, grace_seconds)


def stop_command(process: "subprocess.Popen[bytes]", patterns: List[Pattern[str]], grace_seconds: float) -> None:
    """責務: コマンドのグループを止め、続けて `--kill-pattern` に一致するプロセスを止める。"""
    stop_process_group(process, grace_seconds)
    stop_matching_processes(patterns, grace_seconds)
