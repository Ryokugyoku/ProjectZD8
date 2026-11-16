"""ベースライン許容・エラー判定(README §4)のテスト。ベースラインは --update-baseline で作る。"""

from metrics_support import (BASELINE_REL, MetricsTestCase, nested_ifs,
                             run_tool, swift_func, write)

REL = "ProjectZD8/A.swift"


class BaselineJudgementTests(MetricsTestCase):
    """記録値との比較による警告・エラーの判定。"""

    def record(self, source):
        """責務: ソースを書き、その時点の超過をベースラインへ記録する。"""
        write(self.root, REL, source)
        done = run_tool(self.root, "--update-baseline")
        self.assertEqual(done.code, 0)

    def check(self, source):
        """責務: ソースを書き直して該当ファイルをチェックする。"""
        return run_tool(self.root, write(self.root, REL, source))

    def test_記録値と同じなら警告で成功(self):
        """記録 4 のまま 4 なら warning と [baseline 4] を付け exit 0。"""
        self.record(swift_func(nested_ifs(4)))
        r = self.check(swift_func(nested_ifs(4)))
        self.assertEqual(
            r.warnings,
            [REL + ":1: warning: nesting 4 > 3 (f) [baseline 4]"])
        self.assertEqual(r.errors, [])
        self.assertEqual(r.code, 0)

    def test_記録値より小さければ警告のまま(self):
        """記録 5 で現在 4 は warning [baseline 5] で exit 0。"""
        self.record(swift_func(nested_ifs(5)))
        r = self.check(swift_func(nested_ifs(4)))
        self.assertEqual(
            r.warnings,
            [REL + ":1: warning: nesting 4 > 3 (f) [baseline 5]"])
        self.assertEqual(r.code, 0)

    def test_記録値より大きければエラー(self):
        """記録 4 で現在 5 は error(baseline 表記なし)で exit 1。"""
        self.record(swift_func(nested_ifs(4)))
        r = self.check(swift_func(nested_ifs(5)))
        self.assertEqual(r.errors, [REL + ":1: error: nesting 5 > 3 (f)"])
        self.assertEqual(r.code, 1)

    def test_ベースラインにない超過はエラー(self):
        """ベースラインが無い状態の超過は error で exit 1。"""
        r = self.check(swift_func(nested_ifs(4)))
        self.assertEqual(r.errors, [REL + ":1: error: nesting 4 > 3 (f)"])
        self.assertEqual(r.code, 1)

    def test_関数名が変わるとベースライン外(self):
        """キーは関数名を含むため、改名した関数の超過は error。"""
        self.record(swift_func(nested_ifs(4), name="f"))
        r = self.check(swift_func(nested_ifs(4), name="g"))
        self.assertEqual(r.errors, [REL + ":1: error: nesting 4 > 3 (g)"])

    def test_行がずれても名前で照合する(self):
        """先頭にコメントを足して開始行が変わっても許容され、行は新しい値。"""
        self.record(swift_func(nested_ifs(4)))
        r = self.check(swift_func(nested_ifs(4), prefix="// a\n// b\n"))
        self.assertEqual(
            r.warnings,
            [REL + ":3: warning: nesting 4 > 3 (f) [baseline 4]"])
        self.assertEqual(r.code, 0)

    def test_ベースラインは自動更新されない(self):
        """値が下がっても baseline.json は書き換わらず、次回も旧値で表示。"""
        self.record(swift_func(nested_ifs(5)))
        before = (self.root / BASELINE_REL).read_bytes()
        self.check(swift_func(nested_ifs(4)))
        again = self.check(swift_func(nested_ifs(4)))
        self.assertEqual((self.root / BASELINE_REL).read_bytes(), before)
        self.assertEqual(
            again.warnings,
            [REL + ":1: warning: nesting 4 > 3 (f) [baseline 5]"])


class BaselineKeyTests(MetricsTestCase):
    """同名関数の出現順キーとファイル単位指標のキー。"""

    def two_funcs(self, first_deep, second_deep):
        """責務: 同名 f を2つ持つソースを返す(深さは引数)。"""
        return ("struct A {\n" + swift_func(nested_ifs(first_deep))
                + "}\nstruct B {\n" + swift_func(nested_ifs(second_deep)) + "}\n")

    def test_同名関数は出現順で区別する(self):
        """f#0 だけ超過を記録。f#0 が解消し f#1 が超過すると f#1 は error。"""
        write(self.root, REL, self.two_funcs(4, 1))
        self.assertEqual(run_tool(self.root, "--update-baseline").code, 0)
        path = write(self.root, REL, self.two_funcs(1, 4))
        r = run_tool(self.root, path)
        self.assertEqual(len(r.errors), 1)
        self.assertIn("error: nesting 4 > 3 (f)", r.errors[0])
        self.assertEqual(r.code, 1)

    def test_同名関数の両方を記録すると両方許容(self):
        """f#0 と f#1 の両方を記録すれば、両方 warning で exit 0。"""
        path = write(self.root, REL, self.two_funcs(4, 4))
        self.assertEqual(run_tool(self.root, "--update-baseline").code, 0)
        text = (self.root / BASELINE_REL).read_text(encoding="utf-8")
        self.assertIn("f#0", text)
        self.assertIn("f#1", text)
        r = run_tool(self.root, path)
        self.assertEqual(len(r.warnings), 2)
        self.assertEqual(r.code, 0)

    def test_ファイル単位の指標も許容される(self):
        """file_lines 501 を記録後、同値は warning [baseline 501]、増えると error。"""
        write(self.root, REL, "// x\n" * 501)
        run_tool(self.root, "--update-baseline")
        same = run_tool(self.root, self.root / REL)
        self.assertEqual(
            same.warnings,
            [REL + ":1: warning: file_lines 501 > 500 [baseline 501]"])
        self.assertEqual(same.code, 0)
        path = write(self.root, REL, "// x\n" * 502)
        bigger = run_tool(self.root, path)
        self.assertEqual(
            bigger.errors, [REL + ":1: error: file_lines 502 > 500"])
        self.assertEqual(bigger.code, 1)
