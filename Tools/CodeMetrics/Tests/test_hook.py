"""--hook モード(README §5、§6)のテスト。"""

import json

from metrics_support import (MetricsTestCase, nested_ifs, run_tool,
                             swift_func, write)

DEEP = swift_func(nested_ifs(4))
LINE = "ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"
WARN_LINE = "ProjectZD8/A.swift:1: warning: nesting 4 > 3 (f) [baseline 4]"
NOTE = ("note: 改修したファイルの既存の超過(warning)も、この変更の中で解消する"
        "(共通ルール §5)。解消したら --update-baseline でベースラインから外す。")


class HookTests(MetricsTestCase):
    """標準入力 JSON からの対象取得と終了コード。"""

    def hook(self, payload):
        """責務: JSON を標準入力に流して --hook を実行する。"""
        return run_tool(self.root, "--hook", stdin=json.dumps(payload))

    def test_tool_inputのパスを検査しエラーは2で標準エラー(self):
        """違反があれば exit 2、内容は stderr に出て stdout は空。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        r = self.hook({"tool_input": {"file_path": str(path)}})
        self.assertEqual(r.code, 2)
        self.assertIn(LINE, r.stderr.splitlines())
        self.assertEqual(r.stdout.strip(), "")

    def test_tool_responseのパスにフォールバック(self):
        """tool_input.file_path が無ければ tool_response.filePath を使う。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        r = self.hook({"tool_input": {}, "tool_response": {"filePath": str(path)}})
        self.assertEqual(r.code, 2)
        self.assertIn(LINE, r.stderr.splitlines())

    def test_tool_inputが優先される(self):
        """両方あるとき tool_input.file_path を使う(違反ファイルは input 側)。"""
        bad = write(self.root, "ProjectZD8/A.swift", DEEP)
        ok = write(self.root, "ProjectZD8/B.swift", swift_func("work()"))
        r = self.hook({"tool_input": {"file_path": str(bad)},
                       "tool_response": {"filePath": str(ok)}})
        self.assertEqual(r.code, 2)

    def test_エラーなしは無出力で0(self):
        """違反のないファイルは stdout/stderr とも空で exit 0。"""
        ok = write(self.root, "ProjectZD8/A.swift", swift_func("work()"))
        self.assert_clean(self.hook({"tool_input": {"file_path": str(ok)}}))

    def test_警告のみは2で警告行と注記を標準エラーに出す(self):
        """記録済みの超過だけでも exit 2。warning 行の後に注記が最終行で付く。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        run_tool(self.root, "--update-baseline")
        r = self.hook({"tool_input": {"file_path": str(path)}})
        self.assertEqual(r.code, 2)
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual(r.stderr.splitlines(), [WARN_LINE, NOTE])

    def test_エラーのみは2で注記を出さない(self):
        """エラーだけなら error 行のみで、警告用の注記は出ない。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        r = self.hook({"tool_input": {"file_path": str(path)}})
        self.assertEqual(r.code, 2)
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual(r.stderr.splitlines(), [LINE])
        self.assertNotIn(NOTE, r.stderr)

    def test_エラーと警告が同居すれば両方の行の後に注記が最終行(self):
        """同一ファイルに警告(記録済み)とエラー(新規)があれば両行と末尾の注記。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        run_tool(self.root, "--update-baseline")
        both = DEEP + swift_func(nested_ifs(4), name="g")
        write(self.root, "ProjectZD8/A.swift", both)
        r = self.hook({"tool_input": {"file_path": str(path)}})
        self.assertEqual(r.code, 2)
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual(r.stderr.splitlines(), [
            WARN_LINE, "ProjectZD8/A.swift:12: error: nesting 4 > 3 (g)", NOTE])

    def test_通常モードの警告のみは0のまま(self):
        """退行防止: --hook 以外では警告だけなら exit 0(警告行は出る)。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        run_tool(self.root, "--update-baseline")
        r = run_tool(self.root, path)
        self.assertEqual(r.code, 0)
        self.assertEqual(r.warnings, [WARN_LINE])
        self.assertNotIn(NOTE, r.stdout + r.stderr)

    def test_swift以外のパスは検査せず0(self):
        """.swift 以外のパスは対象外で exit 0、出力なし。"""
        txt = write(self.root, "ProjectZD8/a.txt", "// x\n" * 600)
        self.assert_clean(self.hook({"tool_input": {"file_path": str(txt)}}))

    def test_不正なJSONは0(self):
        """JSON として読めない入力は exit 0。"""
        r = run_tool(self.root, "--hook", stdin="not json {")
        self.assertEqual(r.code, 0)

    def test_パスがないJSONは0(self):
        """file_path も filePath も無い JSON は exit 0。"""
        r = self.hook({"tool_input": {"command": "ls"}})
        self.assertEqual(r.code, 0)
