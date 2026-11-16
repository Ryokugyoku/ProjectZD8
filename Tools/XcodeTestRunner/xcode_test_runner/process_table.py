"""`ps` でプロセス一覧を読み、`--kill-pattern` に一致するプロセスを探す。`pgrep` は使わない。

本ツール自身とその祖先のコマンド行には正規表現そのものが入っていて一致するため、必ず対象から外す。
"""

import os
import subprocess
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Pattern, Sequence, Set, Tuple

PS_TIMEOUT_SECONDS = 10.0
PS_COMMAND_COLUMNS = ["ps", "-axo", "pid=,command="]
PS_PARENT_COLUMNS = ["ps", "-axo", "pid=,ppid="]


class ProcessTableError(Exception):
    """`ps` を実行できなかった、または失敗したことを表す例外。"""


@dataclass(frozen=True)
class ProcessEntry:
    """プロセス一覧の1行(番号とコマンド行)。"""

    pid: int
    command: str


def run_ps(arguments: Sequence[str]) -> str:
    """責務: `ps` を時間上限つきで実行し、標準出力を返す。失敗は `ProcessTableError` にする。"""
    try:
        completed = subprocess.run(
            list(arguments), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, timeout=PS_TIMEOUT_SECONDS, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ProcessTableError("ps を実行できません: {}".format(error))
    if completed.returncode != 0:
        raise ProcessTableError("ps が終了コード {} で失敗しました".format(completed.returncode))
    return completed.stdout.decode("utf-8", errors="replace")


def _split_pid(line: str) -> Optional[Tuple[int, str]]:
    """責務: 先頭の PID と残りに1行を分ける。PID が数字でない行は None。"""
    parts = line.strip().split(None, 1)
    if not parts or not parts[0].isdigit():
        return None
    rest = parts[1] if len(parts) > 1 else ""
    return int(parts[0]), rest


def parse_command_lines(text: str) -> List[ProcessEntry]:
    """責務: `ps -axo pid=,command=` の出力をプロセス一覧へ直す。"""
    entries = []
    for line in text.splitlines():
        split = _split_pid(line)
        if split is not None:
            entries.append(ProcessEntry(pid=split[0], command=split[1]))
    return entries


def parse_parent_lines(text: str) -> Dict[int, int]:
    """責務: `ps -axo pid=,ppid=` の出力を、PID から親 PID への対応表へ直す。"""
    parents = {}
    for line in text.splitlines():
        split = _split_pid(line)
        if split is not None and split[1].strip().isdigit():
            parents[split[0]] = int(split[1].strip())
    return parents


def ancestor_pids(own_pid: int, parents: Dict[int, int]) -> Set[int]:
    """責務: 自分と、親をたどった祖先の PID の集合を返す(たどる回数は表の大きさで打ち切る)。"""
    found = {own_pid}
    current = own_pid
    for _ in range(len(parents) + 1):
        parent = parents.get(current)
        if parent is None or parent <= 0 or parent in found:
            break
        found.add(parent)
        current = parent
    return found


def matching_pids(entries: Iterable[ProcessEntry], patterns: Sequence[Pattern[str]], excluded: Set[int]) -> List[int]:
    """責務: 除外集合に入らず、コマンド行がどれかの正規表現に `re.search` で一致する PID を返す。"""
    return [
        entry.pid for entry in entries
        if entry.pid not in excluded and any(pattern.search(entry.command) for pattern in patterns)
    ]


def excluded_pids(own_pid: int) -> Set[int]:
    """責務: 照合から外す PID(自分・祖先・PID 0 と 1)を求める。親子表が読めなくても自分と親は外す。"""
    excluded = {0, 1, own_pid, os.getppid()}
    try:
        excluded |= ancestor_pids(own_pid, parse_parent_lines(run_ps(PS_PARENT_COLUMNS)))
    except ProcessTableError:
        pass
    return excluded


def find_matching_pids(patterns: Sequence[Pattern[str]], own_pid: Optional[int] = None) -> List[int]:
    """責務: いま動いているプロセスから、正規表現に一致し自分と祖先ではないものの PID を返す。"""
    if not patterns:
        return []
    pid = os.getpid() if own_pid is None else own_pid
    excluded = excluded_pids(pid)
    entries = parse_command_lines(run_ps(PS_COMMAND_COLUMNS))
    return matching_pids(entries, patterns, excluded)
