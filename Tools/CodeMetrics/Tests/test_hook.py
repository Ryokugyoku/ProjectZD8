"""--hook モード(README §5、§6)のテスト。"""

import json

from metrics_support import (MetricsTestCase, nested_ifs, run_tool,
                             swift_func, write)

DEEP = swift_func(nested_ifs(4))
LINE = "ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"


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

    def test_ベースライン許容の警告のみなら無出力で0(self):
        """警告だけ(記録済みの超過)ならエラー無しとして無出力・exit 0。"""
        path = write(self.root, "ProjectZD8/A.swift", DEEP)
        run_tool(self.root, "--update-baseline")
        r = self.hook({"tool_input": {"file_path": str(path)}})
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual(r.stderr.strip(), "")
        self.assertEqual(r.code, 0)

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
