"""プロセスグループや個別のプロセスを SIGTERM → 猶予 → SIGKILL の順で止める。待ちはすべて上限つき。"""

import os
import signal
import subprocess
import time
from typing import Callable, List, Sequence

from .lock_owner import process_exists

CHECK_INTERVAL_SECONDS = 0.05
KILL_SETTLE_SECONDS = 5.0


def wait_until(predicate: Callable[[], bool], timeout: float, interval: float = CHECK_INTERVAL_SECONDS) -> bool:
    """責務: 条件が真になるまで、時間と回数の上限つきで待つ。上限内に真になったかを返す。"""
    deadline = time.monotonic() + timeout
    for _ in range(int(timeout / interval) + 2):
        if predicate():
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(interval, remaining))
    return predicate()


def signal_group(pgid: int, signum: int) -> None:
    """責務: プロセスグループへシグナルを送る。自分のグループや既に空のグループには何もしない。"""
    if pgid <= 1 or pgid == os.getpgrp():
        return
    try:
        os.killpg(pgid, signum)
    except (ProcessLookupError, PermissionError):
        pass


def group_is_gone(process: "subprocess.Popen[bytes]", pgid: int) -> bool:
    """責務: 直下の子を回収したうえで、グループに生きているプロセスが残っていないかを返す。"""
    process.poll()
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def stop_process_group(process: "subprocess.Popen[bytes]", grace_seconds: float) -> None:
    """責務: コマンドのグループへ SIGTERM を送り、猶予後も残れば SIGKILL を送って回収する。"""
    pgid = process.pid
    signal_group(pgid, signal.SIGTERM)
    if wait_until(lambda: group_is_gone(process, pgid), grace_seconds):
        return
    signal_group(pgid, signal.SIGKILL)
    wait_until(lambda: group_is_gone(process, pgid), KILL_SETTLE_SECONDS)
    try:
        process.wait(timeout=KILL_SETTLE_SECONDS)
    except subprocess.TimeoutExpired:
        pass


def signal_pid(pid: int, signum: int) -> None:
    """責務: 1つのプロセスへシグナルを送る。既にいない・権限がない場合は無視する。"""
    if pid <= 1 or pid == os.getpid():
        return
    try:
        os.kill(pid, signum)
    except (ProcessLookupError, PermissionError):
        pass


def alive_pids(pids: Sequence[int]) -> List[int]:
    """責務: 渡した PID のうち、まだ存在するものを返す。"""
    return [pid for pid in pids if process_exists(pid)]


def stop_pids(pids: Sequence[int], grace_seconds: float) -> None:
    """責務: 各プロセスへ SIGTERM を送り、猶予後も残るものへ SIGKILL を送る。"""
    for pid in pids:
        signal_pid(pid, signal.SIGTERM)
    if wait_until(lambda: not alive_pids(pids), grace_seconds):
        return
    for pid in alive_pids(pids):
        signal_pid(pid, signal.SIGKILL)
    wait_until(lambda: not alive_pids(pids), KILL_SETTLE_SECONDS)
