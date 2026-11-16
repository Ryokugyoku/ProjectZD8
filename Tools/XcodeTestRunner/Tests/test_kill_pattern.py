"""--kill-pattern のテスト(README §4 手順4)。時間上限の時だけ、別グループの一致プロセスも止める。"""

import sys
import uuid

from runner_support import SLEEP_FOREVER, TOOL, RunnerTestCase, assert_lock_released

IGNORE_TERM_TARGET = (
    "import signal, sys, time\n"
    "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
    "open(sys.argv[1], 'w').close()\n"
    "time.sleep(30)\n"
)
RUN_NESTED = "import subprocess, sys; sys.exit(subprocess.run(sys.argv[2:-1], timeout=20).returncode)"


class KillPatternTestCase(RunnerTestCase):
    """標的役のプロセスを起動する近道を持つ基底クラス。"""

    def spawn_target(self, code=SLEEP_FOREVER, *args):
        """責務: 一意な名前を引数に持つ標的役を新しいセッションで起動し、(プロセス, 名前) を返す。"""
        token = "zd8-kill-target-" + uuid.uuid4().hex
        return self.spawn(self.py(code, *(list(args) + [token]))), token

    def run_timeout_with_patterns(self, patterns):
        """責務: patterns を --kill-pattern に渡し、時間上限 1 秒を超える子を実行した結果を返す。"""
        options = ["--limit", "1"]
        for pattern in patterns:
            options += ["--kill-pattern", pattern]
        return self.run_runner(options + ["--"] + self.py(SLEEP_FOREVER))

    def assert_stopped(self, proc, what, timeout=3.0):
        """責務: proc が timeout 秒以内に終了することを検証する。"""
        self.wait_for(lambda: proc.poll() is not None, what + " の停止", timeout=timeout)


class KillPatternOnTimeoutTests(KillPatternTestCase):
    """時間上限の時に、一致するプロセスだけを止める。"""

    def test_上限内に終われば標的は止めない(self):
        """責務: コマンドが上限内に終われば --kill-pattern は働かず、標的は生きている。"""
        target, token = self.spawn_target()
        result = self.run_runner(["--limit", "10", "--kill-pattern", token, "--"] + self.py("pass"))
        self.assertEqual(result.code, 0, result.stderr)
        self.assertIsNone(target.poll(), "上限内に終わったのに標的が止められた")

    def test_時間上限で別グループの標的を止める(self):
        """責務: 別のプロセスグループにいる一致プロセスは、時間上限の時に止まる。終了コードは 124。"""
        target, token = self.spawn_target()
        result = self.run_timeout_with_patterns([token])
        self.assertEqual(result.code, 124, result.stderr)
        self.assert_stopped(target, "一致する標的")
        assert_lock_released(self)

    def test_一致しないプロセスは止めない(self):
        """責務: パターンに一致する標的だけが止まり、一致しない標的は生きている。"""
        matched, token = self.spawn_target()
        other, _ = self.spawn_target()
        result = self.run_timeout_with_patterns([token])
        self.assertEqual(result.code, 124, result.stderr)
        self.assert_stopped(matched, "一致する標的")
        self.assertIsNone(other.poll(), "一致しないプロセスが止められた")

    def test_複数のパターンをすべて使う(self):
        """責務: --kill-pattern を2回指定すると、それぞれに一致する標的が両方止まる。"""
        first, first_token = self.spawn_target()
        second, second_token = self.spawn_target()
        result = self.run_timeout_with_patterns([first_token, second_token])
        self.assertEqual(result.code, 124, result.stderr)
        self.assert_stopped(first, "1つ目のパターンの標的")
        self.assert_stopped(second, "2つ目のパターンの標的")

    def test_SIGTERMを無視する標的も止める(self):
        """責務: SIGTERM を無視する標的も、猶予の後の SIGKILL で止まる。"""
        ready = self.path("target-ready")
        target, token = self.spawn_target(IGNORE_TERM_TARGET, ready)
        self.wait_for(ready.exists, "標的の準備")
        result = self.run_timeout_with_patterns([token])
        self.assertEqual(result.code, 124, result.stderr)
        self.assert_stopped(target, "SIGTERM を無視する標的")


class KillPatternSelfExclusionTests(KillPatternTestCase):
    """本ツール自身とその祖先は、コマンド行が一致しても止めない。"""

    def test_ラッパー自身は一致しても止めず124でロックを解放する(self):
        """責務: パターンはラッパーのコマンド行にも一致するが、ラッパーは 124 を返し TIMEOUT 行を出してロックを消す。"""
        _, token = self.spawn_target()
        result = self.run_timeout_with_patterns([token])
        self.assertEqual(result.code, 124, result.stderr)
        self.assertEqual(len(result.lines_starting("TIMEOUT")), 1, result.stderr)
        assert_lock_released(self)

    def test_ラッパーの祖先は一致しても止めない(self):
        """責務: パターンを含む祖父母→親の2段を経由して起動しても、祖先は止められずラッパーの 124 が届く。"""
        target, token = self.spawn_target()
        wrapper = [sys.executable, str(TOOL), "--limit", "1", "--kill-pattern", token, "--"]
        parent = self.py(RUN_NESTED, token, *(wrapper + self.py(SLEEP_FOREVER)))
        grandparent = self.spawn(self.py(RUN_NESTED, token, *parent), env=self.env())
        self.assert_stopped(grandparent, "祖先プロセス", timeout=10.0)
        self.assertEqual(grandparent.returncode, 124, "祖先が止められたか、ラッパーの 124 が届いていない")
        self.assert_stopped(target, "一致する標的")
        assert_lock_released(self)
