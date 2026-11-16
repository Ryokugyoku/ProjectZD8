"""環境変数から、ロックの場所と待ち時間の設定(`TimingSettings`)を読む。"""

import math
import os
from dataclasses import dataclass
from typing import Mapping

from .options import UsageError

LOCK_DIR_ENV = "XCODE_TEST_RUNNER_LOCK_DIR"
POLL_SECONDS_ENV = "XCODE_TEST_RUNNER_POLL_SECONDS"
STALE_SECONDS_ENV = "XCODE_TEST_RUNNER_STALE_SECONDS"
GRACE_SECONDS_ENV = "XCODE_TEST_RUNNER_GRACE_SECONDS"
DEFAULT_POLL_SECONDS = 5.0
DEFAULT_STALE_SECONDS = 30.0
DEFAULT_GRACE_SECONDS = 5.0
LOCK_DIR_NAME = "projectzd8-xcodebuild.lock"


@dataclass(frozen=True)
class TimingSettings:
    """ロックの場所と、ポーリング間隔・回収までの秒数・停止の猶予秒数。"""

    lock_path: str
    poll_seconds: float
    stale_seconds: float
    grace_seconds: float


def default_lock_path(uid: int) -> str:
    """責務: 古い bash スクリプトと共有する既定のロックの場所を返す。"""
    return os.path.join("/private/tmp", "claude-{}".format(uid), LOCK_DIR_NAME)


def read_seconds(environ: Mapping[str, str], name: str, default: float, allow_zero: bool) -> float:
    """責務: 秒数の環境変数を有限の小数として読み、未設定・空なら既定値を返す。不正なら `UsageError`。"""
    text = environ.get(name, "").strip()
    if not text:
        return default
    try:
        value = float(text)
    except ValueError:
        raise UsageError("{} が数値ではありません: {!r}".format(name, text))
    if not math.isfinite(value) or value < 0 or (value == 0 and not allow_zero):
        lower = "0 以上" if allow_zero else "0 より大きい"
        raise UsageError("{} は{}の有限の数値が必要です: {!r}".format(name, lower, text))
    return value


def load_timing_settings(environ: Mapping[str, str]) -> TimingSettings:
    """責務: 環境変数から `TimingSettings` を組み立てる。"""
    lock_path = environ.get(LOCK_DIR_ENV, "") or default_lock_path(os.getuid())
    return TimingSettings(
        lock_path=lock_path,
        poll_seconds=read_seconds(environ, POLL_SECONDS_ENV, DEFAULT_POLL_SECONDS, allow_zero=False),
        stale_seconds=read_seconds(environ, STALE_SECONDS_ENV, DEFAULT_STALE_SECONDS, allow_zero=True),
        grace_seconds=read_seconds(environ, GRACE_SECONDS_ENV, DEFAULT_GRACE_SECONDS, allow_zero=True),
    )
