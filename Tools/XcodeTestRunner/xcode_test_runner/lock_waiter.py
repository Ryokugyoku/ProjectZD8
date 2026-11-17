"""ロックが取れるまで、上限の秒数と回数の範囲でポーリングする。"""

import time
from typing import Callable

from .diagnostics import report_note
from .directory_lock import DirectoryLock


def max_attempts(wait_seconds: float, poll_seconds: float) -> int:
    """責務: 待ち時間とポーリング間隔から、取り直しの最大回数を求める(時間上限の安全網)。"""
    return int(wait_seconds / poll_seconds) + 3


def acquire_with_wait(
    lock: DirectoryLock,
    wait_seconds: float,
    poll_seconds: float,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> bool:
    """責務: `wait_seconds` 秒まで `poll_seconds` 秒ごとにロックを取り直し、取れたかを返す。"""
    deadline = clock() + wait_seconds
    for attempt in range(max_attempts(wait_seconds, poll_seconds)):
        if lock.try_acquire():
            return True
        remaining = deadline - clock()
        if remaining <= 0:
            return False
        if attempt == 0:
            report_note("ロック {} を pid {} が使用中のため待ちます (最大 {} 秒)".format(lock.path, lock.holder_pid(), wait_seconds))
        sleep(min(poll_seconds, remaining))
    return False
