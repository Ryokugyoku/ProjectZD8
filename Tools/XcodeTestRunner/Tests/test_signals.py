"""ラッパーが SIGTERM / SIGINT を受けた時のテスト(README §3 解放・§4 末尾)。子を止め、ロックを消し、128+N を返す。"""

import os
import signal
import time

from runner_support import RunnerTestCase, pid_alive

READY_AND_SLEEP = (
    "import os, signal, sys, time\n"
    "if sys.argv[2] == 'ignore':\n"
    "    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
    "open(sys.argv[1], 'w').write(str(os.getpid()))\n"
    "time.sleep(30)\n"
)


class RunnerSignalTests(RunnerTestCase):
    """実行中のラッパーへシグナルを送ると、子を止めてロックを解放し 128+N で終わる。"""

    def start_running(self, mode="normal"):
        """責務: 子が PID を書いて眠るまでラッパーを進め、(ラッパー, 子の PID) を返す。"""
        pid_file = self.path("child.pid")
        proc = self.start_runner(["--limit", "30", "--"] + self.py(READY_AND_SLEEP, pid_file, mode))
        self.wait_for(lambda: pid_file.exists() and pid_file.read_text() != "", "子の開始")
        return proc, int(pid_file.read_text())

    def assert_stopped_by(self, signum, mode="normal"):
        """責務: ラッパーに signum を送ると 128+signum で終わり、子が止まりロックが消えることを検証する。"""
        proc, child_pid = self.start_running(mode)
        os.kill(proc.pid, signum)
        result = self.finish(proc, timeout=15)
        self.assertEqual(result.code, 128 + signum, result.stderr)
        self.wait_for(lambda: not pid_alive(child_pid), "子の停止", timeout=3.0)
        self.assert_lock_released()
        return result

    def test_SIGTERMで子を止めて143(self):
        """責務: SIGTERM(15)を受けると子を止め、ロックを消して 143 で終わる。"""
        self.assert_stopped_by(signal.SIGTERM)

    def test_SIGINTで子を止めて130(self):
        """責務: SIGINT(2)を受けると子を止め、ロックを消して 130 で終わる。"""
        self.assert_stopped_by(signal.SIGINT)

    def test_SIGTERMを無視する子も猶予の後に止める(self):
        """責務: 子が SIGTERM を無視しても、GRACE_SECONDS の後の SIGKILL で止まり、ラッパーは 143 で終わる。"""
        result = self.assert_stopped_by(signal.SIGTERM, mode="ignore")
        self.assertLess(result.elapsed, 10.0)


class WaitingRunnerSignalTests(RunnerTestCase):
    """ロック待ちの間にシグナルを受けても、他者のロックは消さない。"""

    def test_ロック待ち中のSIGTERMは他者のロックを消さず143(self):
        """責務: 他者のロックを待っている間に SIGTERM を受けると 143 で終わり、子は始まらず、他者のロックは元のまま。"""
        holder = self.spawn_holder()
        self.write_lock(str(holder.pid))
        touched = self.path("touched")
        code = "import sys; open(sys.argv[1], 'w').close()"
        proc = self.start_runner(["--limit", "10", "--lock-wait", "20", "--"] + self.py(code, touched))
        time.sleep(0.8)
        self.assertIsNone(proc.poll(), "ロックの空きを待たずに終わった")
        os.kill(proc.pid, signal.SIGTERM)
        result = self.finish(proc, timeout=10)
        self.assertEqual(result.code, 128 + signal.SIGTERM, result.stderr)
        self.assertFalse(touched.exists(), "ロックを取れていないのにコマンドが実行された")
        self.assertEqual((self.lock_dir / "pid").read_text(), str(holder.pid), "他者のロックが消された")
