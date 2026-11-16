"""ロックの取得と解放のテスト(README §3)。"""

from runner_support import SLEEP_FOREVER, TOUCH, WAIT_FOR_FILE, RunnerTestCase


class LockAcquireTests(RunnerTestCase):
    """実行中はロックのディレクトリがあり、pid はラッパーのプロセス ID。"""

    def test_実行中はロックにラッパーのPIDが書かれている(self):
        """責務: 子の実行中にロックのディレクトリと pid ファイルがあり、中身はラッパーの PID の10進数。"""
        started, release = self.path("started"), self.path("release")
        proc = self.start_runner(["--limit", "20", "--"] + self.py(WAIT_FOR_FILE, started, release))
        self.wait_for(started.exists, "子の開始")
        self.assertTrue(self.lock_dir.is_dir(), "実行中なのにロックのディレクトリが無い")
        self.assertEqual((self.lock_dir / "pid").read_text().strip(), str(proc.pid))
        release.touch()
        self.assertEqual(self.finish(proc).code, 0)
        self.assert_lock_released()

    def test_ロックの親ディレクトリが無ければ作る(self):
        """責務: XCODE_TEST_RUNNER_LOCK_DIR の親が無くても作って実行し、終了後はロックを消す。"""
        self.lock_dir = self.path("a") / "b" / "runner.lock"
        touched = self.path("touched")
        result = self.run_runner(["--limit", "10", "--"] + self.py(TOUCH, touched), env=self.env())
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(touched.exists(), "コマンドが実行されなかった")
        self.assertTrue(self.lock_dir.parent.is_dir(), "親ディレクトリが作られていない")
        self.assert_lock_released()


class LockReleaseTests(RunnerTestCase):
    """どの終わり方でも自分のロックを消してから終わる。"""

    def test_正常終了後にロックが残らない(self):
        """責務: 子が 0 で終わった後、ロックのディレクトリは無い。"""
        result = self.run_runner(["--limit", "10", "--"] + self.py("pass"))
        self.assertEqual(result.code, 0, result.stderr)
        self.assert_lock_released()

    def test_子の失敗後にロックが残らない(self):
        """責務: 子が 0 以外で終わった後も、ロックのディレクトリは無い。"""
        result = self.run_runner(["--limit", "10", "--"] + self.py("import sys; sys.exit(3)"))
        self.assertEqual(result.code, 3, result.stderr)
        self.assert_lock_released()

    def test_時間上限後にロックが残らない(self):
        """責務: 時間上限で止めた後(124)も、ロックのディレクトリは無い。"""
        result = self.run_runner(["--limit", "1", "--"] + self.py(SLEEP_FOREVER))
        self.assertEqual(result.code, 124, result.stderr)
        self.assert_lock_released()

    def test_続けて実行すると毎回ロックを取り直せる(self):
        """責務: 解放が完全なら、同じロック場所で2回続けて実行しても待たずに両方実行される。"""
        for index in range(2):
            touched = self.path("touched-%d" % index)
            result = self.run_runner(["--limit", "10", "--lock-wait", "0", "--"] + self.py(TOUCH, touched))
            self.assertEqual(result.code, 0, result.stderr)
            self.assertTrue(touched.exists(), "%d 回目のコマンドが実行されなかった" % (index + 1))
