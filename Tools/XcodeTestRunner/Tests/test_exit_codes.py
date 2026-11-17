"""終了コードと出力の透過テスト(README §2・§4・§5)。"""

import signal

from runner_support import RunnerTestCase, assert_lock_released

SELF_SIGNAL = "import os, signal, sys; os.kill(os.getpid(), getattr(signal, sys.argv[1]))"
WRITE_BOTH = "import sys; sys.stdout.write(sys.argv[1] + '\\n'); sys.stderr.write(sys.argv[2] + '\\n')"


class ExitCodePassThroughTests(RunnerTestCase):
    """上限内に終わったコマンドの終了コードをそのまま返す。"""

    def run_exit(self, code):
        """責務: 終了コード code で終わる子をラッパー経由で実行した結果を返す。"""
        return self.run_runner(["--limit", "10", "--"] + self.py("import sys; sys.exit(int(sys.argv[1]))", code))

    def test_子が0で終われば0(self):
        """責務: 子の終了コード 0 をそのまま返す。"""
        self.assertEqual(self.run_exit(0).code, 0)

    def test_子が3で終われば3(self):
        """責務: 子の終了コード 3 をそのまま返す(ラッパー自身の 2・124・125 と混ざらない)。"""
        self.assertEqual(self.run_exit(3).code, 3)

    def test_子がSIGTERMで終われば143(self):
        """責務: シグナルで終わった子は 128 + シグナル番号(SIGTERM=15)。"""
        result = self.run_runner(["--limit", "10", "--"] + self.py(SELF_SIGNAL, "SIGTERM"))
        self.assertEqual(result.code, 128 + signal.SIGTERM, result.stderr)

    def test_子がSIGKILLで終われば137(self):
        """責務: シグナルで終わった子は 128 + シグナル番号(SIGKILL=9)。時間上限の 124 にはならない。"""
        result = self.run_runner(["--limit", "10", "--"] + self.py(SELF_SIGNAL, "SIGKILL"))
        self.assertEqual(result.code, 128 + signal.SIGKILL, result.stderr)


class CommandNotRunnableTests(RunnerTestCase):
    """コマンドが見つからない・実行できない場合は理由を出して 127。"""

    def test_存在しないコマンドは127(self):
        """責務: 存在しないパスのコマンドは終了コード 127 で、理由が標準エラーに出る。"""
        missing = self.path("no-such-command-" + self.marker)
        result = self.run_runner(["--limit", "10", "--", str(missing)])
        self.assertEqual(result.code, 127, result.stderr)
        self.assertNotEqual(result.stderr.strip(), "")

    def test_実行権限の無いファイルは127(self):
        """責務: 存在しても実行できないファイルは終了コード 127 で、理由が標準エラーに出る。"""
        script = self.path("not-executable.sh")
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o644)
        result = self.run_runner(["--limit", "10", "--", str(script)])
        self.assertEqual(result.code, 127, result.stderr)
        self.assertNotEqual(result.stderr.strip(), "")

    def test_実行できなければロックを残さない(self):
        """責務: 127 で終わった後もロックは解放されている。"""
        missing = self.path("no-such-command-" + self.marker)
        self.assertEqual(self.run_runner(["--limit", "10", "--", str(missing)]).code, 127)
        assert_lock_released(self)


class OutputPassThroughTests(RunnerTestCase):
    """子の標準出力・標準エラーをそのまま流す。"""

    def test_標準出力と標準エラーをそれぞれ流す(self):
        """責務: 子が書いた行が、ラッパーの標準出力・標準エラーにそれぞれそのまま現れる。"""
        out_text = "OUT-" + self.marker
        err_text = "ERR-" + self.marker
        result = self.run_runner(["--limit", "10", "--"] + self.py(WRITE_BOTH, out_text, err_text))
        self.assertEqual(result.code, 0, result.stderr)
        self.assertIn(out_text + "\n", result.stdout)
        self.assertNotIn(err_text, result.stdout)
        self.assertIn(err_text + "\n", result.stderr)
        self.assertNotIn(out_text, result.stderr)

    def test_失敗した子の出力も流す(self):
        """責務: 終了コードが 0 以外でも子の出力は失われない。"""
        code = "import sys; print(sys.argv[1]); sys.exit(4)"
        result = self.run_runner(["--limit", "10", "--"] + self.py(code, "FAIL-" + self.marker))
        self.assertEqual(result.code, 4, result.stderr)
        self.assertIn("FAIL-" + self.marker, result.stdout)
