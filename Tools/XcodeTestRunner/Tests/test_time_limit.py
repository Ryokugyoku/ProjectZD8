"""時間上限のテスト(README §4)。上限内なら通常終了、超えたら TIMEOUT 行・124 で、子も孫も残さない。"""

import re

from runner_support import SLEEP_FOREVER, RunnerTestCase, pid_alive

IGNORE_TERM = (
    "import os, signal, sys, time\n"
    "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
    "open(sys.argv[1], 'w').write(str(os.getpid()))\n"
    "time.sleep(30)\n"
)
SPAWN_GRANDCHILD = (
    "import subprocess, sys, time\n"
    "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)', sys.argv[-1]],\n"
    "                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
    "open(sys.argv[1], 'w').write(str(child.pid))\n"
    "time.sleep(30)\n"
)


class WithinLimitTests(RunnerTestCase):
    """--limit 秒以内に終われば TIMEOUT にしない。"""

    def test_上限内に終われば通常終了(self):
        """責務: 0.2 秒で終わる子は --limit 5 で通常どおり終了コード 0、TIMEOUT 行は出ない。"""
        result = self.run_runner(["--limit", "5", "--"] + self.py("import time; time.sleep(0.2)"))
        self.assertEqual(result.code, 0, result.stderr)
        self.assertEqual(result.lines_starting("TIMEOUT"), [])
        self.assertLess(result.elapsed, 5.0)


class ExceededLimitTests(RunnerTestCase):
    """--limit を過ぎたら TIMEOUT 行を出し、コマンドを止めて 124。"""

    def test_超過で124と上限秒数を含むTIMEOUT行(self):
        """責務: --limit 2 を過ぎると 124 で、TIMEOUT で始まる行に上限の秒数 2 が含まれる。"""
        result = self.run_runner(["--limit", "2", "--"] + self.py(SLEEP_FOREVER))
        self.assertEqual(result.code, 124, result.stderr)
        lines = result.lines_starting("TIMEOUT")
        self.assertEqual(len(lines), 1, result.stderr)
        self.assertRegex(lines[0], r"(?<![0-9.])2(?![0-9])", "TIMEOUT 行に上限の秒数が無い")
        self.assertGreaterEqual(result.elapsed, 1.9, "上限より前に止めた")
        self.assertLess(result.elapsed, 8.0, "上限を過ぎてもすぐに止めなかった")
        self.assert_lock_released()

    def test_SIGTERMを無視する子も猶予の後にSIGKILLで止まる(self):
        """責務: 子が SIGTERM を無視しても、GRACE_SECONDS(1秒)の後に止まり 124 で、子は残らない。"""
        pid_file = self.path("child.pid")
        env = self.env(XCODE_TEST_RUNNER_GRACE_SECONDS="1")
        result = self.run_runner(["--limit", "1", "--"] + self.py(IGNORE_TERM, pid_file), env=env)
        self.assertEqual(result.code, 124, result.stderr)
        self.assertGreaterEqual(result.elapsed, 1.9, "猶予を待たずに SIGKILL した")
        self.assertLess(result.elapsed, 8.0)
        child_pid = int(pid_file.read_text())
        self.wait_for(lambda: not pid_alive(child_pid), "SIGTERM を無視する子の停止", timeout=3.0)
        self.assert_lock_released()

    def test_子が起動した孫も残らない(self):
        """責務: 同じプロセスグループにいる孫プロセスも、時間上限で止まる。"""
        pid_file = self.path("grandchild.pid")
        result = self.run_runner(["--limit", "1", "--"] + self.py(SPAWN_GRANDCHILD, pid_file))
        self.assertEqual(result.code, 124, result.stderr)
        grandchild = int(pid_file.read_text())
        self.wait_for(lambda: not pid_alive(grandchild), "孫プロセスの停止", timeout=3.0)
        self.assert_lock_released()

    def test_TIMEOUT行は標準エラーに出る(self):
        """責務: 本ツールのメッセージは標準エラーへ出し、標準出力には TIMEOUT 行を出さない。"""
        result = self.run_runner(["--limit", "1", "--"] + self.py(SLEEP_FOREVER))
        self.assertEqual(result.code, 124, result.stderr)
        self.assertFalse(re.search(r"^TIMEOUT", result.stdout, re.MULTILINE), result.stdout)
        self.assertEqual(len(result.lines_starting("TIMEOUT")), 1, result.stderr)
