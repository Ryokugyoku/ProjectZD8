"""ロックの持ち主(`pid` ファイル)を読み、持ち主がいない残骸かどうかを判定する。"""

import errno
import os
import re
import time
from dataclasses import dataclass
from typing import Callable, Optional

PID_FILE_NAME = "pid"
_DIGITS = re.compile(r"\d+", re.ASCII)


@dataclass(frozen=True)
class LockInspection:
    """ロックを調べた結果。`pid` は読めた持ち主の番号(無い・空・数字でなければ None)。"""

    pid: Optional[int]
    abandoned: bool


def pid_file_path(lock_path: str) -> str:
    """責務: ロックディレクトリ内の `pid` ファイルのパスを返す。"""
    return os.path.join(lock_path, PID_FILE_NAME)


def read_owner_pid(lock_path: str) -> Optional[int]:
    """責務: `pid` ファイルの10進数を読む。無い・空・数字でない・読めない場合は None を返す。"""
    try:
        with open(pid_file_path(lock_path), "r", encoding="ascii") as handle:
            text = handle.read(64).strip()
    except (OSError, UnicodeDecodeError):
        return None
    if not _DIGITS.fullmatch(text):
        return None
    return int(text)


def process_exists(pid: int) -> bool:
    """責務: その番号のプロセスが存在するかを、シグナル 0 で確かめる(権限がなくても存在とみなす)。"""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as error:
        return error.errno != errno.ESRCH
    return True


def _is_old(lock_path: str, stale_seconds: float, now: Callable[[], float]) -> bool:
    """責務: ロックディレクトリの更新時刻から `stale_seconds` 以上たったかを返す(無ければ False)。"""
    try:
        modified = os.stat(lock_path).st_mtime
    except FileNotFoundError:
        return False
    return now() - modified >= stale_seconds


def inspect_lock(lock_path: str, stale_seconds: float, now: Callable[[], float] = time.time) -> LockInspection:
    """責務: 既存のロックが回収してよい残骸か(持ち主不在、または pid 不正のまま古い)を判定する。"""
    pid = read_owner_pid(lock_path)
    if pid is not None:
        return LockInspection(pid=pid, abandoned=not process_exists(pid))
    return LockInspection(pid=None, abandoned=_is_old(lock_path, stale_seconds, now))
