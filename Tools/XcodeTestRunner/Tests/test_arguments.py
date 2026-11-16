"""引数の検証テスト(README §2・§5)。不正なら終了コード 2 でコマンドを実行せず、境界の値は受け付ける。"""

from runner_support import TOUCH, RunnerTestCase

INVALID_OPTIONS = {
    "--limit が無い": [],
    "--limit が整数でない": ["--limit", "abc"],
    "--limit が小数": ["--limit", "1.5"],
    "--limit が 0": ["--limit", "0"],
    "--limit が負": ["--limit", "-1"],
    "--lock-wait が負": ["--limit", "5", "--lock-wait", "-1"],
    "--lock-wait が整数でない": ["--limit", "5", "--lock-wait", "abc"],
    "--kill-pattern が不正な正規表現": ["--limit", "5", "--kill-pattern", "("],
}


class InvalidArgumentTests(RunnerTestCase):
    """不正な引数はコマンドを実行せずに終了コード 2。"""

    def assert_rejected(self, options, index=0):
        """責務: options で起動すると終了コード 2・理由の出力ありで、子の目印ファイルが作られないことを検証する。"""
        touched = self.path("touched-%d" % index)
        result = self.run_runner(options + ["--"] + self.py(TOUCH, touched))
        self.assertEqual(result.code, 2, result.stderr)
        self.assertNotEqual(result.stderr.strip(), "", "理由が標準エラーに出ていない")
        self.assertFalse(touched.exists(), "不正な引数なのにコマンドが実行された")

    def test_不正な引数はいずれも終了コード2で実行しない(self):
        """責務: --limit 無し・整数でない・0・負、--lock-wait 負・整数でない、不正な正規表現をそれぞれ拒否する。"""
        for index, (name, options) in enumerate(INVALID_OPTIONS.items()):
            with self.subTest(name):
                self.assert_rejected(options, index)

    def test_区切りの後ろが空なら終了コード2(self):
        """責務: `--` の後ろにコマンドが無い場合は理由を出して終了コード 2。"""
        result = self.run_runner(["--limit", "5", "--"])
        self.assertEqual(result.code, 2, result.stderr)
        self.assertNotEqual(result.stderr.strip(), "", "理由が標準エラーに出ていない")


class AcceptedArgumentTests(RunnerTestCase):
    """範囲の境界ちょうどの値は受け付けてコマンドを実行する。"""

    def assert_accepted(self, options):
        """責務: options で起動すると子が実行され、終了コード 0 になることを検証する。"""
        touched = self.path("touched")
        result = self.run_runner(options + ["--"] + self.py(TOUCH, touched))
        self.assertEqual(result.code, 0, result.stderr)
        self.assertTrue(touched.exists(), "受け付けるはずの引数でコマンドが実行されなかった")

    def test_limit_1は受け付ける(self):
        """責務: --limit の下限 1 は有効。"""
        self.assert_accepted(["--limit", "1"])

    def test_lock_wait_0は受け付ける(self):
        """責務: --lock-wait の下限 0 は有効で、ロックが空いていれば実行される。"""
        self.assert_accepted(["--limit", "5", "--lock-wait", "0"])

    def test_kill_patternは複数指定できる(self):
        """責務: 正しい正規表現の --kill-pattern を2回指定しても受け付ける。"""
        self.assert_accepted(["--limit", "5", "--kill-pattern", "a+b", "--kill-pattern", "^c$"])
