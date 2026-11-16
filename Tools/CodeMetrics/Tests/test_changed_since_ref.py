"""--changed-since の REF 許可リストと不正 REF の拒否(README §4.1)のテスト。"""

import os

from metrics_support import (MetricsTestCase, make_root, nested_ifs,
                             run_git, run_tool, swift_func, write)

DEEP = swift_func(nested_ifs(4))


class RefAllowlistTests(MetricsTestCase):
    """許可文字・先頭・長さの外にある REF は git に渡さず exit 1。"""

    def setUp(self):
        super().setUp()
        self.cwd = make_root(self)

    def assert_rejected(self, result):
        """責務: exit 1 かつ理由が標準エラーにあることを検証する。"""
        self.assertEqual(result.code, 1)
        self.assertTrue(result.stderr.strip())

    def reject_ref(self, ref):
        """責務: 実 git リポジトリで ref を渡し、拒否されることを検証して結果を返す。"""
        run_git(self.root, "init")
        r = run_tool(self.root, "--changed-since", ref, cwd=self.cwd)
        self.assert_rejected(r)
        return r

    def test_ハイフン始まりのREFは拒否(self):
        """--changed-since -x は exit 1 と stderr。"""
        self.assert_rejected(run_tool(self.root, "--changed-since", "-x"))

    def test_output指定のREFでファイルを作らせない(self):
        """--changed-since --output=foo は exit 1 と stderr、foo は作られない。"""
        r = run_tool(self.root, "--changed-since", "--output=foo",
                     cwd=self.cwd)
        self.assert_rejected(r)
        self.assertFalse((self.root / "foo").exists())
        self.assertFalse((self.cwd / "foo").exists())

    def test_等号形式のハイフン始まりREFも拒否(self):
        """--changed-since=-x(argparse が受理する形)も exit 1 と stderr。"""
        self.assert_rejected(run_tool(self.root, "--changed-since=-x"))

    def test_セミコロンを含むREFは拒否(self):
        """a;b は許可文字外なので exit 1 と stderr。"""
        self.reject_ref("a;b")

    def test_コマンド置換のREFは拒否しファイルを作らない(self):
        """$(touch pwned) は exit 1 と stderr で、pwned はルートにもカレントにも作られない。"""
        self.reject_ref("$(touch pwned)")
        self.assertFalse((self.root / "pwned").exists())
        self.assertFalse((self.cwd / "pwned").exists())
        self.assertFalse(os.path.exists("pwned"))

    def test_バッククォートのREFは拒否(self):
        """`x` は許可文字外なので exit 1 と stderr。"""
        self.reject_ref("`x`")

    def test_201文字のREFは拒否(self):
        """長さ 201 の REF は上限超過で exit 1 と stderr。"""
        self.reject_ref("a" * 201)

    def test_空文字のREFは拒否(self):
        """空文字の REF は exit 1 と stderr。"""
        self.reject_ref("")

    def test_存在しないREFは拒否(self):
        """形式は正しいが実在しない REF は exit 1 と stderr。"""
        run_git(self.root, "init")
        write(self.root, "ProjectZD8/A.swift", swift_func("work()"))
        run_git(self.root, "add", "-A")
        run_git(self.root, "commit", "-m", "init")
        self.assert_rejected(run_tool(self.root, "--changed-since",
                                      "no-such-ref-xyz"))


class ValidRefTests(MetricsTestCase):
    """許可リストを通る REF は通常どおり使える。"""

    def test_HEADチルダ1が使える(self):
        """HEAD~1 は 2 コミットの実リポジトリで有効で、直近コミットの違反だけを報告する。"""
        run_git(self.root, "init")
        write(self.root, "Old.swift", DEEP)
        run_git(self.root, "add", "-A")
        run_git(self.root, "commit", "-m", "base")
        write(self.root, "New.swift", DEEP)
        run_git(self.root, "add", "-A")
        run_git(self.root, "commit", "-m", "second")
        r = run_tool(self.root, "--changed-since", "HEAD~1")
        self.assertEqual(r.errors, ["New.swift:1: error: nesting 4 > 3 (f)"])
        self.assertEqual(r.code, 1)
