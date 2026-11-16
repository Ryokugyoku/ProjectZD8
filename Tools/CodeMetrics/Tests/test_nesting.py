"""制御構造のネスト(README §2)の数え方テスト。制御構文ごとの段数。"""

from metrics_support import MetricsTestCase, nested_ifs, swift_func

VIOLATION4 = ["ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"]


class NestingBoundaryTests(MetricsTestCase):
    """nesting の上限 3 の境界。"""

    def test_3段は違反ではない(self):
        """if が3段は上限ちょうどで出力なし。"""
        self.assert_clean(self.check_swift(swift_func(nested_ifs(3))))

    def test_4段は違反(self):
        """if が4段は nesting 4 > 3。"""
        r = self.check_swift(swift_func(nested_ifs(4)))
        self.assertEqual(r.errors, VIOLATION4)
        self.assertEqual(r.code, 1)

    def test_for_if_while_if_は4(self):
        """README の例: for { if { while { if { } } } } は 4。"""
        body = ("for i in xs {\nif a {\nwhile b {\nif c { work() }\n}\n}\n}")
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)

    def test_repeat_do_が段に数えられる(self):
        """repeat と do も段に数える: repeat/do/if/if で 4。"""
        body = "repeat {\ndo {\nif a {\nif b { work() }\n}\n}\n} while c"
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)


class NestingElseCatchTests(MetricsTestCase):
    """else / catch / else if / guard の段の扱い。"""

    def test_else本体は同じ段_3は許容(self):
        """if {} else { if { if {} } } は else が1段目で最大3。"""
        body = "if a { work() } else {\nif b {\nif c { work() }\n}\n}"
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_else本体の下に3段で4(self):
        """else が1段目なので、その中に if を3段重ねると 4。"""
        body = "if a { work() } else {\nif b {\nif c {\nif d { work() }\n}\n}\n}"
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)

    def test_else_if本体は同じ段(self):
        """else if の本体も1段目。中に if 2段で合計3、違反なし。"""
        body = ("if a { work() } else if b {\nif c {\nif d { work() }\n}\n}")
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_catch本体は同じ段(self):
        """do { } catch { if { if { } } } は do/catch が1段目で最大3。"""
        body = "do { try g() } catch {\nif a {\nif b { work() }\n}\n}"
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_catch本体の下に3段で4(self):
        """catch が1段目なので、その中に if を3段重ねると 4。"""
        body = ("do { try g() } catch {\nif a {\nif b {\nif c { work() }\n}\n}\n}")
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)

    def test_guard_elseが段に数えられる(self):
        """guard ... else { の本体は1段。中に if 3段で 4。"""
        body = ("guard ok else {\nif a {\nif b {\nif c { work() }\n}\n}\n}")
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)


class NestingSwitchTests(MetricsTestCase):
    """switch と case の段の扱い。"""

    def test_guard後のswitch_if_は2(self):
        """README の例: guard の後の switch { case: if { } } は 2(違反なし)。"""
        body = ("guard let v = x else { return }\nswitch v {\ncase 1:\n"
                "if v > 0 { work() }\ndefault:\nbreak\n}")
        self.assert_clean(self.check_swift(swift_func(body)))

    def test_for_switch_if_if_は4(self):
        """for(1) switch(2) if(3) if(4)。case ラベルは段に数えない。"""
        body = ("for i in xs {\nswitch i {\ncase 1:\nif a {\nif b { work() }\n}\n"
                "default:\nbreak\n}\n}")
        r = self.check_swift(swift_func(body))
        self.assertEqual(r.errors, VIOLATION4)

    def test_for_switch_if_は3(self):
        """case を複数並べても段は増えず、for/switch/if で 3。"""
        body = ("for i in xs {\nswitch i {\ncase 1:\nif a { work() }\n"
                "case 2:\nif b { work() }\ndefault:\nbreak\n}\n}")
        self.assert_clean(self.check_swift(swift_func(body)))
