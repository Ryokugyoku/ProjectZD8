"""`mkdir` の成功で取るマシン全体のロック。取得・残骸の回収・自分のロックだけの解放を担う。"""

import os
import shutil
from typing import Optional

from .diagnostics import report_note
from .lock_owner import inspect_lock, pid_file_path, read_owner_pid
from .signal_guard import signals_deferred

MAX_RECLAIMS_PER_TRY = 3


class DirectoryLock:
    """ディレクトリとその中の `pid` ファイルで表すロック。古い bash スクリプトと同じ形。"""

    def __init__(self, path: str, stale_seconds: float, own_pid: Optional[int] = None) -> None:
        """責務: ロックの場所・回収までの秒数・自分の PID を保持する(未取得で始める)。"""
        self.path = path
        self.stale_seconds = stale_seconds
        self.own_pid = os.getpid() if own_pid is None else own_pid
        self._owned = False

    @property
    def owned(self) -> bool:
        """自分がこのロックを持っているか。"""
        return self._owned

    def holder_pid(self) -> Optional[int]:
        """責務: いまロックを持っているプロセスの番号を返す(読めなければ None)。"""
        return read_owner_pid(self.path)

    def try_acquire(self) -> bool:
        """責務: 待たずに1回ロックを取りにいく。残骸なら回収して取り直す(回数に上限あり)。"""
        parent = os.path.dirname(os.path.abspath(self.path))
        os.makedirs(parent, exist_ok=True)
        for _ in range(MAX_RECLAIMS_PER_TRY + 1):
            if self._create():
                return True
            if not self._reclaim_if_abandoned():
                return False
        return False

    def release(self) -> None:
        """責務: 自分が取ったロックだけを消す。`pid` が自分でなければ消さずに知らせる。"""
        if not self._owned:
            return
        self._owned = False
        holder = read_owner_pid(self.path)
        if holder != self.own_pid:
            report_note("ロック {} の持ち主が自分 (pid {}) ではない ({}) ため消しません".format(self.path, self.own_pid, holder))
            return
        shutil.rmtree(self.path, ignore_errors=True)

    def _create(self) -> bool:
        """責務: `mkdir` でロックを作り、成功したら `pid` に自分の PID を書く。既にあれば False。"""
        with signals_deferred():
            try:
                os.mkdir(self.path)
            except FileExistsError:
                return False
            self._owned = True
            self._write_pid()
        return True

    def _write_pid(self) -> None:
        """責務: `pid` ファイルに自分の PID を10進数で書く。書けなければロックを消して例外を返す。"""
        try:
            with open(pid_file_path(self.path), "w", encoding="ascii") as handle:
                handle.write("{}\n".format(self.own_pid))
        except OSError:
            self._owned = False
            shutil.rmtree(self.path, ignore_errors=True)
            raise

    def _reclaim_if_abandoned(self) -> bool:
        """責務: 既存のロックが残骸なら消して True を返す。生きている持ち主のロックは消さない。"""
        inspection = inspect_lock(self.path, self.stale_seconds)
        if not inspection.abandoned:
            return False
        if read_owner_pid(self.path) != inspection.pid:
            return True
        try:
            shutil.rmtree(self.path)
        except FileNotFoundError:
            return True
        report_note("持ち主のいないロック {} を回収しました (pid: {})".format(self.path, inspection.pid))
        return True
