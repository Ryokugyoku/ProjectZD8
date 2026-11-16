"""SIGINT / SIGTERM を受けた時に、処理を例外で中断させて後始末へ進ませる。"""

import signal
import threading
from contextlib import contextmanager
from typing import Dict, Iterator, Optional

HANDLED_SIGNALS = (signal.SIGINT, signal.SIGTERM)


class ReceivedSignal(Exception):
    """本ツールが停止のシグナルを受けたことを表す例外。"""

    def __init__(self, signum: int) -> None:
        """責務: 受けたシグナル番号を保持する。"""
        super().__init__("signal {}".format(signum))
        self.signum = signum


def _in_main_thread() -> bool:
    """責務: シグナルハンドラーとマスクを扱えるメインスレッドかどうかを返す。"""
    return threading.current_thread() is threading.main_thread()


@contextmanager
def signals_deferred() -> Iterator[None]:
    """責務: ブロックの間だけ停止シグナルの配送を OS で遅らせ、ロック作成を途中で切らせない。

    子プロセスはこのマスクを引き継ぐため、コマンドの起動には使わない(`SignalGuard.deferred` を使う)。
    """
    if not _in_main_thread():
        yield
        return
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, HANDLED_SIGNALS)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


class SignalGuard:
    """停止シグナルを受けたら `ReceivedSignal` を投げるハンドラーを、with の間だけ入れる。

    後始末を始めたら `disarm` で例外を止め、受けたシグナルは記録だけにする。
    """

    def __init__(self) -> None:
        """責務: 未設置・武装済みの状態で初期化する。"""
        self._armed = True
        self._deferring = False
        self._deferred_signal: Optional[int] = None
        self._previous: Dict[int, object] = {}
        self.pending: Optional[int] = None

    def __enter__(self) -> "SignalGuard":
        """責務: メインスレッドなら停止シグナルのハンドラーを差し替える。"""
        if _in_main_thread():
            for signum in HANDLED_SIGNALS:
                self._previous[signum] = signal.signal(signum, self._handle)
        return self

    def __exit__(self, *exc_info: object) -> None:
        """責務: 差し替えたハンドラーを元に戻す。"""
        self._armed = False
        for signum, handler in self._previous.items():
            signal.signal(signum, handler)  # type: ignore[arg-type]
        self._previous.clear()

    def disarm(self) -> None:
        """責務: 以降のシグナルで例外を投げないようにし、後始末を中断させない。"""
        self._armed = False

    @contextmanager
    def deferred(self) -> Iterator[None]:
        """責務: ブロックの間に来たシグナルの例外を、ブロックを抜けた直後まで遅らせる(マスクは変えない)。

        ブロックが最後まで(または return で)抜けた時だけ、遅らせたシグナルを `ReceivedSignal` で投げる。
        ブロックが例外で抜けた時はその例外を優先し、遅らせたシグナルは捨てる(起動失敗なら 127 を返すため)。
        """
        self._deferring = True
        block_completed = False
        try:
            yield
            block_completed = True
        finally:
            signum = self._end_deferral()
            if block_completed:
                self._raise_if_armed(signum)

    def _end_deferral(self) -> Optional[int]:
        """責務: 遅延を終え、遅らせていたシグナルの番号を取り出して消す(無ければ None)。"""
        self._deferring = False
        signum = self._deferred_signal
        self._deferred_signal = None
        return signum

    def _raise_if_armed(self, signum: Optional[int]) -> None:
        """責務: シグナルの番号があり、まだ武装中なら `ReceivedSignal` を投げる。"""
        if signum is not None and self._armed:
            self._armed = False
            raise ReceivedSignal(signum)

    def _handle(self, signum: int, _frame: object) -> None:
        """責務: シグナルを記録し、武装中なら `ReceivedSignal` を投げる(遅延中は記録だけ)。"""
        if self.pending is None:
            self.pending = signum
        if not self._armed:
            return
        if self._deferring:
            self._deferred_signal = signum
            return
        self._armed = False
        raise ReceivedSignal(signum)
