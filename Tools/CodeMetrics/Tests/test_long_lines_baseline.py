"""long_lines のベースライン・--hook・出力順(README §4〜§6)のテスト。"""

import json

from metrics_support import (BASELINE_REL, MetricsTestCase, nested_ifs,
                             run_tool, swift_func, write)

REL = "ProjectZD8/A.swift"
SHORT = "let a = 1"


def long_row(length=161):
    """責務: 先頭が // で、文字数がちょうど length の行を作る。"""
    return "//" + "x" * (length - 2)


def source_with(long_at, total):
    """責務: total 行のうち long_at(1 始まり)の行だけを 161 文字にしたソースを作る。"""
    rows = [long_row() if i + 1 in long_at else SHORT for i in range(total)]
    return "\n".join(rows) + "\n"


class LongLinesBaselineTests(MetricsTestCase):
    """記録・許容・増加・減少。"""

    def recorded(self):
        """責務: baseline.json を読み込んで files 部分を返す。"""
        text = (self.root / BASELINE_REL).read_text(encoding="utf-8")
        return json.loads(text)["files"]

    def prepare(self, long_at, total=6):
        """責務: ソースを書いてベースラインを更新し、そのパスを返す。"""
        path = write(self.root, REL, source_with(long_at, total))
        self.assertEqual(run_tool(self.root, "--update-baseline").code, 0)
        return path

    def test_update_baselineが値を記録する(self):
        """files に long_lines の値(超過行の数)が記録される。"""
        self.prepare({1, 3})
        self.assertEqual(self.recorded(), {REL: {"long_lines": 2}})

    def test_超過のないファイルは記録しない(self):
        """長い行のないファイルはベースラインに現れない。"""
        write(self.root, REL, SHORT + "\n")
        run_tool(self.root, "--update-baseline")
        self.assertEqual(self.recorded(), {})

    def test_記録値と同じなら警告で終了コード0(self):
        """記録値と同じなら warning: で末尾に [baseline 2]、終了コード 0。"""
        path = self.prepare({1, 3})
        r = run_tool(self.root, path)
        self.assertEqual(r.warnings, [
            REL + ":1: warning: long_lines 2 > 0 (lines 1, 3) [baseline 2]"])
        self.assertEqual(r.errors, [])
        self.assertEqual(r.code, 0)

    def test_記録値より増えたらエラー(self):
        """長い行を 1 つ足して 3 件になるとエラー(終了コード 1)で警告は出ない。"""
        path = self.prepare({1, 3})
        write(self.root, REL, source_with({1, 3, 5}, 6))
        r = run_tool(self.root, path)
        self.assertEqual(r.errors, [
            REL + ":1: error: long_lines 3 > 0 (lines 1, 3, 5)"])
        self.assertEqual(r.code, 1)

    def test_記録値より減っても警告のまま(self):
        """1 件に減ったら警告のままで、記録値は [baseline 2] のまま。"""
        path = self.prepare({1, 3})
        write(self.root, REL, source_with({3}, 6))
        r = run_tool(self.root, path)
        self.assertEqual(r.warnings, [
            REL + ":3: warning: long_lines 1 > 0 (lines 3) [baseline 2]"])
        self.assertEqual(r.code, 0)

    def test_全部直せば出力なし(self):
        """長い行をすべて直すと警告も出ず終了コード 0。"""
        path = self.prepare({1, 3})
        write(self.root, REL, source_with(set(), 6))
        self.assert_clean(run_tool(self.root, path))


class LongLinesHookTests(MetricsTestCase):
    """--hook での扱い。"""

    def hook(self, path):
        """責務: ファイルパスを持つフック JSON を流して --hook を実行する。"""
        payload = {"tool_input": {"file_path": str(path)}}
        return run_tool(self.root, "--hook", stdin=json.dumps(payload))

    def test_長い行は標準エラーに出して終了コード2(self):
        """違反があれば stderr に long_lines のエラー、stdout は空、終了コード 2。"""
        path = write(self.root, REL, source_with({2}, 3))
        r = self.hook(path)
        self.assertEqual(r.code, 2)
        self.assertIn(REL + ":2: error: long_lines 1 > 0 (lines 2)",
                      r.stderr.splitlines())
        self.assertEqual(r.stdout.strip(), "")

    def test_ベースライン許容なら無出力で0(self):
        """記録済みと同じ件数なら何も出さず終了コード 0。"""
        path = write(self.root, REL, source_with({2}, 3))
        run_tool(self.root, "--update-baseline")
        r = self.hook(path)
        self.assertEqual((r.stdout.strip(), r.stderr.strip(), r.code), ("", "", 0))

    def test_ベースラインより増えたら終了コード2(self):
        """許容中のファイルに長い行を足すと標準エラーにエラーが出て 2。"""
        path = write(self.root, REL, source_with({2}, 3))
        run_tool(self.root, "--update-baseline")
        write(self.root, REL, source_with({1, 2}, 3))
        r = self.hook(path)
        self.assertEqual(r.code, 2)
        self.assertIn(REL + ":1: error: long_lines 2 > 0 (lines 1, 2)",
                      r.stderr.splitlines())


class LongLinesOrderTests(MetricsTestCase):
    """他の指標と同時に違反した時の並び順(README §6)。"""

    NEST = nested_ifs(4)

    def test_同じパスでは行順(self):
        """4 行目の長い行はそれより前(1 行目)の関数のネスト違反の後に出る。"""
        text = swift_func(self.NEST) + long_row() + "\n"
        long_no = len(text.splitlines())
        r = self.check_swift(text)
        self.assertEqual(r.errors, [
            REL + ":1: error: nesting 4 > 3 (f)",
            "%s:%d: error: long_lines 1 > 0 (lines %d)" % (REL, long_no, long_no)])

    def test_長い行が先なら長い行が先に出る(self):
        """1 行目の長い行は、後ろの行から始まる関数のエラーより先に出る。"""
        text = long_row() + "\n" + swift_func(self.NEST)
        r = self.check_swift(text)
        self.assertEqual(r.errors, [
            REL + ":1: error: long_lines 1 > 0 (lines 1)",
            REL + ":2: error: nesting 4 > 3 (f)"])

    def test_同じ行は指標ID順(self):
        """同じ 1 行目なら指標ID(文字列)順で long_lines が nesting より先に出る。"""
        head = "func f() { //"
        first = head + "x" * (161 - len(head))
        text = first + "\n" + self.NEST + "\n}\n"
        r = self.check_swift(text)
        self.assertEqual(r.errors, [
            REL + ":1: error: long_lines 1 > 0 (lines 1)",
            REL + ":1: error: nesting 4 > 3 (f)"])

    def test_パス順(self):
        """B.swift より A.swift の long_lines が先に出る。"""
        b = write(self.root, "ProjectZD8/B.swift", source_with({1}, 1))
        a = write(self.root, REL, source_with({1}, 1))
        r = run_tool(self.root, b, a)
        self.assertEqual([ln.split(":")[0] for ln in r.errors],
                         [REL, "ProjectZD8/B.swift"])
