"""XcodeTestRunner テスト共通の補助。CLI の起動、一時ロック、プロセスの起動と後始末、上限つきの待ちだけを担う。

どのテストもロックは一時ディレクトリ配下(XCODE_TEST_RUNNER_LOCK_DIR)に置き、既定の本物のロックには触らない。
テストが起動するプロセスの引数には必ずテストごとに一意な目印(uuid)を入れ、後始末ではその目印で探して止める。
"""

import contextlib
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TOOL = REPO / "Tools" / "XcodeTestRunner" / "run_xcodebuild.py"
RUN_TIMEOUT = 30
REAP_TIMEOUT = 5
PS_TIMEOUT = 10
SLEEP_FOREVER = "import time; time.sleep(30)"
WAIT_FOR_FILE = (
    "import os, sys, time\n"
    "open(sys.argv[1], 'w').close()\n"
    "deadline = time.time() + 15\n"
    "while not os.path.exists(sys.argv[2]) and time.time() < deadline:\n"
    "    time.sleep(0.05)\n"
)
TOUCH = "import sys; open(sys.argv[1], 'w').close()"


class Result:
    """ラッパーの実行結果。終了コード・標準出力・標準エラー・経過秒数を保持する。"""

    def __init__(self, code, stdout, stderr, elapsed):
        """責務: 実行結果の各値を保持する。"""
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.elapsed = elapsed

    def lines_starting(self, prefix):
        """責務: 標準エラーのうち prefix で始まる行だけを返す。"""
        return [ln for ln in self.stderr.splitlines() if ln.startswith(prefix)]


def runner_env(lock_dir, overrides=None):
    """責務: ロック場所を一時パスに向け、待ち時間を短くした環境変数を返す。"""
    env = dict(os.environ)
    env.update({
        "XCODE_TEST_RUNNER_LOCK_DIR": str(lock_dir),
        "XCODE_TEST_RUNNER_POLL_SECONDS": "0.1",
        "XCODE_TEST_RUNNER_STALE_SECONDS": "30",
        "XCODE_TEST_RUNNER_GRACE_SECONDS": "0.5",
    })
    env.update(overrides or {})
    return env


def pid_alive(pid):
    """責務: pid のプロセスが存在し、ゾンビでもないかを ps で判定する(タイムアウト付き)。"""
    done = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)],
                          capture_output=True, text=True, timeout=PS_TIMEOUT)
    state = done.stdout.strip()
    return bool(state) and not state.startswith("Z")


def wait_until(predicate, timeout=5.0, interval=0.05):
    """責務: predicate が真になるまで最大 timeout 秒だけ待ち、最後の判定結果を返す。"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return bool(predicate())


def kill_marked(marker):
    """責務: コマンド行に marker を含むプロセス(テスト自身を除く)をすべて SIGKILL する。"""
    done = subprocess.run(["ps", "-axww", "-o", "pid=,command="],
                          capture_output=True, text=True, timeout=PS_TIMEOUT)
    for line in done.stdout.splitlines():
        pid_text, _, command = line.strip().partition(" ")
        if marker in command and int(pid_text) != os.getpid():
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.kill(int(pid_text), signal.SIGKILL)


def reap(proc):
    """責務: 新しいセッションで起動した proc のプロセスグループを SIGKILL し、上限つきで回収する。"""
    if proc.poll() is None:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(proc.pid, signal.SIGKILL)
    with contextlib.suppress(subprocess.TimeoutExpired):
        proc.communicate(timeout=REAP_TIMEOUT)


class RunnerTestCase(unittest.TestCase):
    """一時ロック・ラッパー起動・プロセス後始末の近道を持つ基底クラス。"""

    def setUp(self):
        """責務: 一時ディレクトリ・ロック場所・一意な目印を用意し、プロセスの後始末を登録する。"""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(os.path.realpath(tmp.name))
        self.lock_dir = self.tmp / "runner.lock"
        self.marker = "zd8-runner-test-" + uuid.uuid4().hex
        self.procs = []
        self.addCleanup(self._cleanup_processes)

    def _cleanup_processes(self):
        """責務: このテストが起動したプロセスと、目印を持つ子孫をすべて止めて回収する。"""
        for proc in self.procs:
            reap(proc)
        kill_marked(self.marker)

    def path(self, name):
        """責務: 一時ディレクトリ配下のパスを返す。"""
        return self.tmp / name

    def py(self, code, *args):
        """責務: 目印を末尾の引数に持つ `python -c code args...` のコマンド列を返す。"""
        return [sys.executable, "-c", code] + [str(a) for a in args] + [self.marker]

    def env(self, **overrides):
        """責務: このテスト用のロック場所と短い待ち時間を持つ環境変数を返す。"""
        return runner_env(self.lock_dir, overrides)

    def run_runner(self, args, env=None, timeout=RUN_TIMEOUT):
        """責務: ラッパーを CLI 経由で起動して終了まで待ち(タイムアウト付き)、結果を返す。"""
        cmd = [sys.executable, str(TOOL)] + [str(a) for a in args]
        started = time.monotonic()
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              env=env or self.env(), start_new_session=True)
        return Result(done.returncode, done.stdout, done.stderr, time.monotonic() - started)

    def start_runner(self, args, env=None):
        """責務: ラッパーを新しいセッションで非同期に起動し、後始末の対象に登録して返す。"""
        cmd = [sys.executable, str(TOOL)] + [str(a) for a in args]
        return self.spawn(cmd, env=env or self.env(), capture=True)

    def finish(self, proc, timeout=RUN_TIMEOUT):
        """責務: 非同期に起動したラッパーの終了を上限つきで待ち、結果を返す。"""
        started = time.monotonic()
        out, err = proc.communicate(timeout=timeout)
        return Result(proc.returncode, out, err, time.monotonic() - started)

    def spawn(self, cmd, env=None, capture=False):
        """責務: 任意のコマンドを新しいセッションで起動し、後始末の対象に登録して返す。"""
        stream = subprocess.PIPE if capture else subprocess.DEVNULL
        proc = subprocess.Popen(cmd, stdout=stream, stderr=stream, text=True,
                                env=env, start_new_session=True)
        self.procs.append(proc)
        return proc

    def spawn_holder(self):
        """責務: ロックの持ち主役として、しばらく生き続けるプロセスを起動して返す。"""
        return self.spawn(self.py(SLEEP_FOREVER, "holder"))

    def write_lock(self, pid_text):
        """責務: 一時ロックのディレクトリを作り、pid_text(None なら pid ファイル無し)を書く。"""
        self.lock_dir.mkdir()
        if pid_text is not None:
            (self.lock_dir / "pid").write_text(pid_text)

    def wait_for(self, predicate, what, timeout=5.0):
        """責務: predicate が上限内に真にならなければ what を示してテストを失敗させる。"""
        if not wait_until(predicate, timeout=timeout):
            self.fail("%s が %.1f 秒以内に成り立たなかった" % (what, timeout))

    def assert_lock_released(self):
        """責務: 一時ロックのディレクトリが残っていないことを検証する。"""
        self.assertFalse(self.lock_dir.exists(), "ロックが解放されずに残っている")
