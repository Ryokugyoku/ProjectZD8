"""1ファイルの関数数(README §3)の境界と数え方のテスト。"""

from metrics_support import MetricsTestCase

VIOLATION = ["ProjectZD8/A.swift:1: error: function_count 21 > 20"]


def funcs(count, start=0):
    """責務: 空の func を count 個並べたソースを返す。"""
    return "".join("func fn%d() {\n}\n" % (start + i) for i in range(count))


class FunctionCountBoundaryTests(MetricsTestCase):
    """function_count の上限 20 の境界。"""

    def test_20個は違反ではない(self):
        """func 20 個は上限ちょうどで出力なし。"""
        self.assert_clean(self.check_swift(funcs(20)))

    def test_21個は違反(self):
        """func 21 個は function_count 21 > 20(行 1、関数名なし)。"""
        r = self.check_swift(funcs(21))
        self.assertEqual(r.errors, VIOLATION)
        self.assertEqual(r.code, 1)


class FunctionCountRuleTests(MetricsTestCase):
    """数える対象と数えない対象。"""

    def test_計算プロパティとアクセサは数えない(self):
        """func 20 個 + 計算プロパティ・get/set・willSet/didSet は 20 のまま。"""
        extra = ("var p: Int {\nreturn 1\n}\n"
                 "var q: Int {\nget { return 1 }\nset { work() }\n}\n"
                 "var r: Int = 0 {\nwillSet { work() }\ndidSet { work() }\n}\n")
        self.assert_clean(self.check_swift(funcs(20) + extra))

    def test_ネスト関数は数えない(self):
        """外側 20 個のうち1つが内部に関数を持っても 20(ネストを数えれば 21)。"""
        src = funcs(19) + "func outer() {\nfunc inner() {\n}\nwork()\n}\n"
        self.assert_clean(self.check_swift(src))

    def test_init_deinit_subscriptを数える(self):
        """init + deinit + subscript + func 18 個 = 21 で違反。"""
        src = ("class C {\ninit() {\n}\ndeinit {\n}\n"
               "subscript(i: Int) -> Int {\nreturn i\n}\n" + funcs(18) + "}\n")
        r = self.check_swift(src)
        self.assertEqual(r.errors, VIOLATION)

    def test_init_deinit_subscript込みで20は許容(self):
        """init + deinit + subscript + func 17 個 = 20 で出力なし。"""
        src = ("class C {\ninit() {\n}\ndeinit {\n}\n"
               "subscript(i: Int) -> Int {\nreturn i\n}\n" + funcs(17) + "}\n")
        self.assert_clean(self.check_swift(src))

    def test_extensionの関数は合算する(self):
        """型本体 11 個 + extension 10 個 = 21 で違反。"""
        src = ("struct S {\n" + funcs(11) + "}\nextension S {\n"
               + funcs(10, 11) + "}\n")
        r = self.check_swift(src)
        self.assertEqual(r.errors, VIOLATION)

    def test_extension合算で20は許容(self):
        """型本体 10 個 + extension 10 個 = 20 で出力なし。"""
        src = ("struct S {\n" + funcs(10) + "}\nextension S {\n"
               + funcs(10, 10) + "}\n")
        self.assert_clean(self.check_swift(src))
