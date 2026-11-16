"""ファイル指定モードの対象選別と終了コード(README §5、§6)のテスト。"""

import os

from metrics_support import (MetricsTestCase, make_root, nested_ifs,
                             run_tool, swift_func, write)
import subprocess
import sys

DEEP = swift_func(nested_ifs(4))


class TargetSelectionTests(MetricsTestCase):
    """対象ファイルの選別。"""

    def test_swift以外は黙って飛ばす(self):
        """.swift 以外は内容が違反級でも無視され、出力なしで exit 0。"""
        txt = write(self.root, "ProjectZD8/Notes.txt", "// x\n" * 600)
        py = write(self.root, "ProjectZD8/tool.py", DEEP)
        self.assert_clean(run_tool(self.root, txt, py))

    def test_存在しないファイルは黙って飛ばす(self):
        """存在しない .swift は無視されて exit 0。"""
        self.assert_clean(run_tool(self.root, self.root / "Missing.swift"))

    def test_存在しないファイルがあっても他は検査する(self):
        """存在しないファイルと違反ファイルを同時に渡すと違反だけ報告。"""
        bad = write(self.root, "ProjectZD8/A.swift", DEEP)
        r = run_tool(self.root, self.root / "Missing.swift", bad)
        self.assertEqual(
            r.errors, ["ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"])
        self.assertEqual(r.code, 1)

    def test_対象が0件なら成功(self):
        """swift 以外と欠損だけなら対象 0 件で exit 0、出力なし。"""
        txt = write(self.root, "a.md", "text\n")
        self.assert_clean(run_tool(self.root, txt, self.root / "none.swift"))

    def test_違反なしは出力なしで0(self):
        """違反のない swift は出力なし・exit 0。"""
        ok = write(self.root, "ProjectZD8/Ok.swift", swift_func("work()"))
        self.assert_clean(run_tool(self.root, ok))


class ExitCodeTests(MetricsTestCase):
    """lizard が使えない場合の終了コード。"""

    def test_lizard未導入は理由を標準エラーに出して3(self):
        """lizard を ImportError にする偽モジュールを PYTHONPATH 先頭に置くと exit 3 と stderr 出力。"""
        fake = make_root(self)
        write(fake, "lizard.py", 'raise ImportError("hidden for test")\n')
        env = dict(os.environ)
        old = env.get("PYTHONPATH")
        env["PYTHONPATH"] = str(fake) + (os.pathsep + old if old else "")
        probe = subprocess.run([sys.executable, "-c", "import lizard"],
                               env=env, timeout=60, capture_output=True)
        self.assertNotEqual(probe.returncode, 0, "lizard を隠せない環境")
        path = write(self.root, "ProjectZD8/A.swift", swift_func("work()"))
        done = run_tool(self.root, path, env=env)
        self.assertEqual(done.code, 3)
        self.assertTrue(done.stderr.strip())
