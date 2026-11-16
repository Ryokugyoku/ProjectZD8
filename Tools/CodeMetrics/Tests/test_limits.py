"""循環的複雑度・認知的複雑度・関数行数・ファイル行数の境界値テスト(README §1)。"""

from metrics_support import (MetricsTestCase, body_of_length, flat_ifs,
                             swift_func)


def cognitive_source(extra_else):
    """責務: 認知的複雑度 15(else 付きで 16)・CCN 10・ネスト 3 の関数を作る。"""
    triple = "if a%d {\nif b%d {\nif c%d { work() }\n}\n}"
    parts = [triple % (1, 1, 1), triple % (2, 2, 2), flat_ifs(2)]
    last = "if g9 { work() }"
    if extra_else:
        last = "if g9 { work() } else { work() }"
    return swift_func("\n".join(parts + [last]))


class CyclomaticLimitTests(MetricsTestCase):
    """cyclomatic の上限 10 の境界。"""

    def test_ccn_10は違反ではない(self):
        """if 9個 = CCN 10 は上限ちょうどで出力なし。"""
        self.assert_clean(self.check_swift(swift_func(flat_ifs(9))))

    def test_ccn_11は違反(self):
        """if 10個 = CCN 11 は上限超過で exit 1。"""
        r = self.check_swift(swift_func(flat_ifs(10)))
        self.assertEqual(r.errors,
                         ["ProjectZD8/A.swift:1: error: cyclomatic 11 > 10 (f)"])
        self.assertEqual(r.code, 1)


class CognitiveLimitTests(MetricsTestCase):
    """cognitive の上限 15 の境界。"""

    def test_cognitive_15は違反ではない(self):
        """入れ子 if 2組(6+6)と独立 if 3個で 15。CCN は 10 で他指標も上限内。"""
        self.assert_clean(self.check_swift(cognitive_source(False)))

    def test_cognitive_16は違反(self):
        """else を1つ足すと 16(CCN は 10 のまま)で cognitive のみ違反。"""
        r = self.check_swift(cognitive_source(True))
        self.assertEqual(r.errors,
                         ["ProjectZD8/A.swift:1: error: cognitive 16 > 15 (f)"])
        self.assertEqual(r.code, 1)


class FunctionLengthLimitTests(MetricsTestCase):
    """function_length の上限 80 の境界(宣言行から閉じ括弧まで)。"""

    def test_80行は違反ではない(self):
        """宣言から閉じ括弧まで 80 行ちょうどは出力なし。"""
        self.assert_clean(self.check_swift(body_of_length(80)))

    def test_81行は違反(self):
        """81 行は function_length 81 > 80。"""
        r = self.check_swift(body_of_length(81))
        self.assertEqual(
            r.errors, ["ProjectZD8/A.swift:1: error: function_length 81 > 80 (f)"])
        self.assertEqual(r.code, 1)


class FileLinesLimitTests(MetricsTestCase):
    """file_lines の上限 500 の境界(末尾改行の有無を含む)。"""

    def test_500行_末尾改行あり(self):
        """改行 500 個は上限ちょうどで出力なし。"""
        self.assert_clean(self.check_swift("// x\n" * 500))

    def test_501行_末尾改行あり(self):
        """改行 501 個は違反。行は 1、関数名なし。"""
        r = self.check_swift("// x\n" * 501)
        self.assertEqual(
            r.errors, ["ProjectZD8/A.swift:1: error: file_lines 501 > 500"])
        self.assertEqual(r.code, 1)

    def test_500行_末尾改行なし(self):
        """最終行が改行なしでも1行と数え、500 行なら違反ではない。"""
        self.assert_clean(self.check_swift("\n".join(["// x"] * 500)))

    def test_501行_末尾改行なし(self):
        """最終行が改行なしの 501 行は違反として 501 と報告する。"""
        r = self.check_swift("\n".join(["// x"] * 501))
        self.assertEqual(
            r.errors, ["ProjectZD8/A.swift:1: error: file_lines 501 > 500"])
