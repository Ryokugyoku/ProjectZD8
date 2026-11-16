"""ネスト計測で無視・分離する対象(README §2): クロージャ、文字列、コメント、ネスト関数、try。"""

from metrics_support import MetricsTestCase, nested_ifs, swift_func

STRING_NOISE = '"{ if { if { if { if { while { for {"'


class NestingClosureTests(MetricsTestCase):
    """クロージャは段に数えない。"""

    def test_クロージャを挟んでも段は増えない(self):
        """if/if { run { if } } は if 3 つだけで 3(クロージャを数えれば 4)。"""
        body = "if a {\nif b {\nrun {\nif c { work() }\n}\n}\n}"
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_クロージャ内の4段は4と報告(self):
        """クロージャ内に if 4段なら値は 4(クロージャを数えれば 5)。"""
        body = "run {\n%s\n}" % nested_ifs(4)
        r = self.check_swift(swift_func(body))
        self.assertEqual(
            r.errors, ["ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"])


class NestingStringCommentTests(MetricsTestCase):
    """文字列とコメントの中の括弧・キーワードは無視する。"""

    def test_文字列内の括弧とキーワード(self):
        """3段の if と、開き括弧とキーワードだらけの文字列でも 3 のまま。"""
        body = "let s = %s\n%s" % (STRING_NOISE, nested_ifs(3))
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_文字列内の閉じ括弧(self):
        """閉じ括弧だけの文字列が段の計算を壊さない。"""
        body = 'let s = "} } } }"\n%s' % nested_ifs(3)
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_複数行文字列内を無視する(self):
        """\"\"\" で囲んだ複数行文字列内の { と if は数えない。"""
        body = ('let s = """\nif a {\nif b {\nif c {\nif d {\nwhile e {\n"""\n%s'
                % nested_ifs(3))
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_行コメントを無視する(self):
        """// 以降の括弧とキーワードは数えない。"""
        body = "// if a { if b { if c { if d {\n%s" % nested_ifs(3)
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_ブロックコメントを無視する(self):
        """/* */ の中の括弧とキーワードは複数行でも数えない。"""
        body = "/* if a {\nif b {\nif c {\nif d { */\n%s" % nested_ifs(3)
        self.assert_clean(self.check_swift(swift_func(body)))


class NestingFunctionAndTryTests(MetricsTestCase):
    """ネスト関数の分離と try の扱い。"""

    def test_ネスト関数は外側の段を引き継がない(self):
        """外側 if 2段の中のネスト関数 inner が自前で 4 段なら inner は 4(6 ではない)。"""
        body = ("if a {\nif b {\nfunc inner() {\n%s\n}\n}\n}" % nested_ifs(4))
        r = self.check_swift(swift_func(body, name="outer"))
        self.assertIn("ProjectZD8/A.swift:4: error: nesting 4 > 3 (inner)",
                      r.errors)
        self.assertFalse([e for e in r.errors if "nesting 6" in e])

    def test_浅いネスト関数は違反にならない(self):
        """外側 if 3段の中に浅い inner を定義しても、全体で違反なし。"""
        body = ("if a {\nif b {\nif c {\nfunc inner() {\nif d { work() }\n}\n}\n}\n}")
        self.assert_clean(self.check_swift(swift_func(body, name="outer")))

    def test_tryだけの関数は違反なし(self):
        """try foo() だけの関数は nesting 0 で出力なし。"""
        src = "func f() throws {\ntry foo()\n}\n"
        self.assert_clean(self.check_swift(src))

    def test_tryは段に数えない(self):
        """if 3段の最内に try があっても 3(try を入れ子に数えれば 4)。"""
        body = "if a {\nif b {\nif c {\ntry foo()\n}\n}\n}"
        self.assert_clean(self.check_swift(swift_func(body)))
