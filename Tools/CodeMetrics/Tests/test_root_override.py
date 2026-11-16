"""ルートの決め方(README §4.1)のテスト。--root は廃止、CODE_METRICS_ROOT だけが上書きできる。"""

import subprocess
import sys

from metrics_support import (MetricsTestCase, TOOL, nested_ifs, run_tool,
                             swift_func, tool_env, write)

DEEP = swift_func(nested_ifs(4))


class RootOverrideTests(MetricsTestCase):
    """CODE_METRICS_ROOT の検証と --root の廃止。"""

    def assert_rejected(self, result):
        """責務: exit 1 かつ理由が標準エラーにあることを検証する。"""
        self.assertEqual(result.code, 1)
        self.assertTrue(result.stderr.strip())

    def test_ルート内の違反は報告される(self):
        """対照: 環境変数で指したルート内の違反は報告され exit 1。"""
        r = self.check_swift(DEEP)
        self.assertEqual(r.errors, ["ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"])
        self.assertEqual(r.code, 1)

    def test_存在しないルートは拒否(self):
        """CODE_METRICS_ROOT が存在しないディレクトリなら exit 1 と stderr。"""
        r = run_tool(self.root / "missing-dir", self.root / "A.swift")
        self.assert_rejected(r)

    def test_ルートがファイルなら拒否(self):
        """CODE_METRICS_ROOT が通常ファイルでも exit 1 と stderr。"""
        plain = write(self.root, "plain.txt", "x\n")
        self.assert_rejected(run_tool(plain, plain))

    def test_root_オプションは受け付けない(self):
        """--root を渡すと終了コードは 0 以外で、理由が標準エラーに出る。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        done = subprocess.run(
            [sys.executable, str(TOOL), "--root", str(self.root), str(path)],
            env=tool_env(self.root), timeout=60, capture_output=True,
            text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertTrue(done.stderr.strip())
