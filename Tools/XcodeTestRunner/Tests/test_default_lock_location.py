"""既定のロック場所のテスト(README §3「場所」)。

XCODE_TEST_RUNNER_LOCK_DIR が無い・空なら `<HOME>/Library/Caches/ProjectZD8/xcodebuild.lock` を使う。
実際のホームに触れないよう、どのテストも HOME を一時ディレクトリへ差し替える(HOME を外す場合は検証しない)。
"""

from runner_support import WAIT_FOR_FILE, RunnerTestCase, assert_lock_released

LOCK_DIR_ENV = "XCODE_TEST_RUNNER_LOCK_DIR"


class DefaultLockLocationTests(RunnerTestCase):
    """ロック場所の指定が無い・空の時は、HOME 配下のユーザー専用キャッシュ置き場を使う。"""

    def home_env(self, lock_dir_value):
        """責務: HOME を一時ディレクトリにし、ロック場所の変数を lock_dir_value(None なら外す)にした環境を返す。"""
        home = self.path("home")
        home.mkdir()
        env = self.env(HOME=str(home))
        env.pop(LOCK_DIR_ENV)
        if lock_dir_value is not None:
            env[LOCK_DIR_ENV] = lock_dir_value
        self.assertTrue(env["HOME"].startswith(str(self.tmp)), "HOME が一時ディレクトリを向いていない")
        return env

    def assert_default_lock_used(self, env):
        """責務: 実行中は HOME 配下の既定の場所に pid=ラッパーのロックがあり、終了後に消えることを検証する。"""
        self.lock_dir = self.path("home") / "Library" / "Caches" / "ProjectZD8" / "xcodebuild.lock"
        started, release = self.path("started"), self.path("release")
        args = ["--limit", "20", "--lock-wait", "0", "--"] + self.py(WAIT_FOR_FILE, started, release)
        proc = self.start_runner(args, env=env)
        self.wait_for(started.exists, "子の開始")
        self.assertTrue(self.lock_dir.is_dir(), "既定の場所にロックが無い")
        self.assertEqual((self.lock_dir / "pid").read_text().strip(), str(proc.pid))
        release.touch()
        result = self.finish(proc)
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(self.lock_dir.parent.is_dir(), "既定の場所の親ディレクトリが作られていない")
        assert_lock_released(self)

    def test_指定が無ければHOME配下の既定の場所を使う(self):
        """責務: 変数を外すと、まだ無い Library/Caches/ProjectZD8 を作ってその中にロックを置き、終了後に消す。"""
        self.assert_default_lock_used(self.home_env(None))

    def test_空文字列の指定は未設定として扱う(self):
        """責務: 変数が空文字列でも、HOME 配下の既定の場所を使う。"""
        self.assert_default_lock_used(self.home_env(""))


class ExplicitLockLocationTests(RunnerTestCase):
    """ロック場所を指定した時は、HOME 配下には何も作らない。"""

    def test_指定した場所を使いHOME配下には作らない(self):
        """責務: 変数で一時ロックを指定すると、子は実行されロックは解放され、HOME は空のまま。"""
        home = self.path("home")
        home.mkdir()
        touched = self.path("touched")
        code = "import sys; open(sys.argv[1], 'w').close()"
        args = ["--limit", "10", "--lock-wait", "0", "--"] + self.py(code, touched)
        result = self.run_runner(args, env=self.env(HOME=str(home)))
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(touched.exists(), "コマンドが実行されなかった")
        self.assertEqual(list(home.rglob("*")), [], "ロック場所を指定したのに HOME 配下に作られた")
        assert_lock_released(self)
