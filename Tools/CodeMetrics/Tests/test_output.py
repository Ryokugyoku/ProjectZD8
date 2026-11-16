"""出力形式と並び順(README §6)のテスト。"""

import re

from metrics_support import (MetricsTestCase, nested_ifs, run_tool,
                             swift_func, write)

LINE_RE = re.compile(
    r"^(?P<path>[^:]+):(?P<line>\d+): (?P<sev>error|warning): "
    r"(?P<id>[a-z_]+) (?P<val>\d+) > (?P<limit>\d+)"
    r"(?: \((?P<name>[^)]+)\))?(?: \[baseline (?P<base>\d+)\])?$")
DEEP = swift_func(nested_ifs(4))


def mixed_function():
    """責務: CCN 12 とネスト 4 を同時に超える(認知的複雑度は 10)関数を返す。"""
    cases = "\n".join("case %d: work()" % i for i in range(1, 9))
    body = ("if a {\nif b {\nif c {\nswitch v {\n%s\ndefault: work()\n}\n}\n}\n}"
            % cases)
    return swift_func(body)


class OutputFormatTests(MetricsTestCase):
    """1件1行の書式。"""

    def test_関数単位の行は開始行と関数名を持つ(self):
        """宣言が3行目の関数は :3: で関数名つき、書式正規表現に一致。"""
        path = write(self.root, "ProjectZD8/Sub/A.swift",
                     swift_func(nested_ifs(4), prefix="// a\n// b\n"))
        r = run_tool(self.root, path)
        self.assertEqual(
            r.errors, ["ProjectZD8/Sub/A.swift:3: error: nesting 4 > 3 (f)"])
        self.assertTrue(LINE_RE.match(r.errors[0]))

    def test_ファイル単位の行は1行目で関数名なし(self):
        """file_lines は行 1・関数名なしの書式。"""
        path = write(self.root, "A.swift", "// x\n" * 501)
        r = run_tool(self.root, path)
        m = LINE_RE.match(r.errors[0])
        self.assertEqual(m.group("line"), "1")
        self.assertIsNone(m.group("name"))
        self.assertEqual(m.group("id"), "file_lines")

    def test_相対パスはルート基準でスラッシュ区切り(self):
        """絶対パスで渡しても出力はルートからの `/` 区切り。"""
        path = write(self.root, "ProjectZD8/X/Y/A.swift", DEEP)
        r = run_tool(self.root, path)
        self.assertTrue(r.errors[0].startswith("ProjectZD8/X/Y/A.swift:1:"))
        self.assertNotIn(str(self.root), r.errors[0])


class OutputOrderTests(MetricsTestCase):
    """パス順、行順、指標ID順。"""

    def test_パス順(self):
        """B, A の順に渡しても A のあとに B の順で出る。"""
        b = write(self.root, "B.swift", DEEP)
        a = write(self.root, "A.swift", DEEP)
        r = run_tool(self.root, b, a)
        self.assertEqual(r.errors, ["A.swift:1: error: nesting 4 > 3 (f)",
                                    "B.swift:1: error: nesting 4 > 3 (f)"])

    def test_同じパス内は行順(self):
        """行 2 と行 12 の関数は数値順(2 の次に 12)で出る。"""
        early = "// pad\n" + swift_func(nested_ifs(4), name="early")
        src = early + "\n" * 5 + swift_func(nested_ifs(4), name="late")
        path = write(self.root, "A.swift", src)
        r = run_tool(self.root, path)
        lines = [int(e.split(":")[1]) for e in r.errors]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0], 2)
        self.assertGreater(lines[1], 10)
        self.assertEqual(lines, sorted(lines))

    def test_同じ行は指標ID順(self):
        """同一関数の cyclomatic と nesting は cyclomatic が先。"""
        path = write(self.root, "A.swift", mixed_function())
        r = run_tool(self.root, path)
        ids = [LINE_RE.match(e).group("id") for e in r.errors]
        self.assertEqual(ids, ["cyclomatic", "nesting"])
        self.assertEqual({e.split(":")[1] for e in r.errors}, {"1"})

    def test_ファイル単位と関数単位の行順(self):
        """行 1 のファイル単位 file_lines が、行 1 の関数より先に並ぶか同順位で整列。"""
        src = swift_func(nested_ifs(4)) + "// x\n" * 500
        path = write(self.root, "A.swift", src)
        r = run_tool(self.root, path)
        keys = [(int(e.split(":")[1]), LINE_RE.match(e).group("id"))
                for e in r.errors]
        self.assertEqual(len(keys), 2)
        self.assertEqual(keys, sorted(keys))
