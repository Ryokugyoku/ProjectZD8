"""ロックによる直列化のテスト(README §3)。他者のロックがある間は始まらず、上限を過ぎたら 125。"""

import shutil
import time

from runner_support import TOUCH, RunnerTestCase, assert_lock_released, spawn_holder

RECORD_INTERVAL = (
    "import sys, time\n"
    "start = time.time()\n"
    "time.sleep(0.6)\n"
    "open(sys.argv[1], 'w').write('%r %r' % (start, time.time()))\n"
)


class LockTimeoutTests(RunnerTestCase):
    """生きている持ち主のロックがある間は実行せず、--lock-wait を過ぎたら 125。"""

    def hold_lock(self):
        """責務: 生きている持ち主役を起動し、その PID を書いたロックを作って PID の文字列を返す。"""
        holder = spawn_holder(self)
        self.write_lock(str(holder.pid))
        return str(holder.pid)

    def assert_lock_timeout(self, result, touched, owner):
        """責務: 125・LOCK_TIMEOUT 行あり・子は未実行・他者のロックは元のまま、を検証する。"""
        self.assertEqual(result.code, 125, result.stderr)
        self.assertEqual(len(result.lines_starting("LOCK_TIMEOUT")), 1, result.stderr)
        self.assertFalse(touched.exists(), "ロックを取れていないのにコマンドが実行された")
        self.assertTrue(self.lock_dir.is_dir(), "他者のロックが消された")
        self.assertEqual((self.lock_dir / "pid").read_text(), owner)

    def test_lock_waitを過ぎると125(self):
        """責務: --lock-wait 1 の間はロックが空かないので、約1秒待ってから 125 と LOCK_TIMEOUT 行で終わる。"""
        owner = self.hold_lock()
        touched = self.path("touched")
        result = self.run_runner(["--limit", "10", "--lock-wait", "1", "--"] + self.py(TOUCH, touched))
        self.assert_lock_timeout(result, touched, owner)
        self.assertGreaterEqual(result.elapsed, 0.9, "--lock-wait の秒数だけ待っていない")
        self.assertLess(result.elapsed, 8.0)

    def test_lock_wait_0はすぐ125(self):
        """責務: --lock-wait 0 は待たない。取り直し間隔を 3 秒にしても、その間隔を待たずに 125 で終わる。"""
        owner = self.hold_lock()
        touched = self.path("touched")
        env = self.env(XCODE_TEST_RUNNER_POLL_SECONDS="3")
        result = self.run_runner(["--limit", "10", "--lock-wait", "0", "--"] + self.py(TOUCH, touched), env=env)
        self.assert_lock_timeout(result, touched, owner)
        self.assertLess(result.elapsed, 2.5, "--lock-wait 0 なのに取り直し間隔を待った")


class LockHandOverTests(RunnerTestCase):
    """待っている間にロックが空けば、取り直して実行する。"""

    def test_待機中にロックが外れたら実行して終了コードを返す(self):
        """責務: 持ち主のロックがある間は子が始まらず、ロックが消えた後に子が実行されて終了コード 5 が返る。"""
        holder = spawn_holder(self)
        self.write_lock(str(holder.pid))
        touched = self.path("touched")
        code = "import sys; open(sys.argv[1], 'w').close(); sys.exit(5)"
        proc = self.start_runner(["--limit", "10", "--lock-wait", "15", "--"] + self.py(code, touched))
        time.sleep(0.8)
        self.assertIsNone(proc.poll(), "ロックの空きを待たずに終わった")
        self.assertFalse(touched.exists(), "他者のロックがある間にコマンドが始まった")
        shutil.rmtree(str(self.lock_dir))
        result = self.finish(proc)
        self.assertEqual(result.code, 5, result.stderr)
        self.assertTrue(touched.exists(), "ロックが空いた後もコマンドが実行されなかった")
        assert_lock_released(self)


class ConcurrentRunnerTests(RunnerTestCase):
    """2つのラッパーを同時に起動しても、子の実行区間は重ならない。"""

    def read_interval(self, path):
        """責務: 子が書いた「開始時刻 終了時刻」を読み、浮動小数の組で返す。"""
        start, end = path.read_text().split()
        return float(start), float(end)

    def test_同時に起動しても子は1本ずつ実行される(self):
        """責務: 2本とも終了コード 0 で、一方の子の終了がもう一方の子の開始より前(区間が重ならない)。"""
        records = [self.path("first"), self.path("second")]
        procs = [self.start_runner(["--limit", "10", "--lock-wait", "20", "--"] + self.py(RECORD_INTERVAL, record))
                 for record in records]
        results = [self.finish(proc) for proc in procs]
        self.assertEqual([r.code for r in results], [0, 0], [r.stderr for r in results])
        first, second = sorted(self.read_interval(record) for record in records)
        self.assertLessEqual(first[1], second[0], "2つの子の実行区間が重なった: %r %r" % (first, second))
        assert_lock_released(self)
