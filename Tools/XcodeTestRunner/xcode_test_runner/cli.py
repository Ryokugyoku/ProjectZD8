"""コマンドライン入口。引数の検証 → ロック取得 → 実行と時間上限 → ロック解放の流れをつなぐ。"""

import os
import sys
from typing import Optional, Sequence

from .command_runner import (
    SIGNAL_EXIT_BASE, CommandLaunchError, start_command, stop_command, wait_with_limit,
)
from .diagnostics import report_line, report_note
from .directory_lock import DirectoryLock
from .lock_waiter import acquire_with_wait
from .options import RunOptions, UsageError, parse_arguments
from .signal_guard import ReceivedSignal, SignalGuard
from .timing_settings import TimingSettings, load_timing_settings

EXIT_UNEXPECTED = 1
EXIT_USAGE = 2
EXIT_TIMEOUT = 124
EXIT_LOCK_TIMEOUT = 125
EXIT_LAUNCH_FAILED = 127


def run_command(options: RunOptions, settings: TimingSettings, guard: SignalGuard) -> int:
    """責務: コマンドを起動して上限まで待ち、超過・中断・例外の時はグループと一致プロセスを止める。"""
    process = None
    try:
        with guard.deferred():
            process = start_command(options.command)
        exit_code = wait_with_limit(process, options.limit_seconds)
    except CommandLaunchError as error:
        report_note(str(error))
        return EXIT_LAUNCH_FAILED
    except BaseException:
        guard.disarm()
        if process is not None:
            stop_command(process, options.kill_patterns, settings.grace_seconds)
        raise
    if exit_code is not None:
        return exit_code
    guard.disarm()
    report_line("TIMEOUT: コマンドが --limit {} 秒を超えたため停止します (プロセスグループ {})".format(
        options.limit_seconds, process.pid))
    stop_command(process, options.kill_patterns, settings.grace_seconds)
    return EXIT_TIMEOUT


def acquire_and_run(lock: DirectoryLock, options: RunOptions, settings: TimingSettings, guard: SignalGuard) -> int:
    """責務: ロックを待って取り、取れたらコマンドを実行する。待ち時間を過ぎたら 125 を返す。"""
    if not acquire_with_wait(lock, options.lock_wait_seconds, settings.poll_seconds):
        report_line("LOCK_TIMEOUT: ロック {} を --lock-wait {} 秒以内に取れませんでした (持ち主 pid: {})".format(
            lock.path, options.lock_wait_seconds, lock.holder_pid()))
        return EXIT_LOCK_TIMEOUT
    return run_command(options, settings, guard)


def run_with_lock(options: RunOptions, settings: TimingSettings) -> int:
    """責務: シグナルを例外に変える範囲で実行し、どの経路でも自分が取ったロックを解放する。"""
    lock = DirectoryLock(settings.lock_path, settings.stale_seconds)
    with SignalGuard() as guard:
        try:
            return acquire_and_run(lock, options, settings, guard)
        except ReceivedSignal as received:
            guard.disarm()
            report_note("シグナル {} を受けたため終了します".format(received.signum))
            return SIGNAL_EXIT_BASE + received.signum
        except Exception as error:  # noqa: BLE001 - 想定外の失敗も理由を出してロックを解放する
            guard.disarm()
            report_note("想定外のエラーで終了します: {!r}".format(error))
            return EXIT_UNEXPECTED
        finally:
            guard.disarm()
            lock.release()


def main(argv: Optional[Sequence[str]] = None) -> int:
    """責務: 引数と環境変数を検証し、不正なら 2 を返す。正しければロックつきで実行する。"""
    arguments = sys.argv[1:] if argv is None else list(argv)
    try:
        options = parse_arguments(arguments)
        settings = load_timing_settings(os.environ)
    except UsageError as error:
        report_note("引数が不正です: {}".format(error))
        return EXIT_USAGE
    return run_with_lock(options, settings)
