"""入力の安全性(README §4.1)のテスト。ルート外・リンクされたベースライン。"""

import json

from metrics_support import (BASELINE_REL, MetricsTestCase, make_root,
                             nested_ifs, run_tool, swift_func, write)

DEEP = swift_func(nested_ifs(4))
NESTING_ERROR = "ProjectZD8/A.swift:1: error: nesting 4 > 3 (f)"


class OutsideRootTests(MetricsTestCase):
    """ルートの実パスの外にある対象は黙って飛ばす。"""

    def setUp(self):
        super().setUp()
        self.outside = make_root(self)

    def test_ルート内の違反は報告される(self):
        """対照: ルート内の違反ファイルは報告され exit 1。"""
        r = self.check_swift(DEEP)
        self.assertEqual(r.errors, [NESTING_ERROR])
        self.assertEqual(r.code, 1)

    def test_ルート外のFILE引数は飛ばす(self):
        """実パスがルート外の違反 .swift は出力なしで exit 0。"""
        bad = write(self.outside, "Out.swift", DEEP)
        self.assert_clean(run_tool(self.root, bad))

    def test_ルート外を指すシンボリックリンクは飛ばす(self):
        """ルート内のリンクが外の違反ファイルを指すなら、出力なしで exit 0。"""
        bad = write(self.outside, "Out.swift", DEEP)
        link = self.root / "ProjectZD8" / "Link.swift"
        link.parent.mkdir(parents=True)
        link.symlink_to(bad)
        self.assert_clean(run_tool(self.root, link))

    def test_hookのルート外パスは黙って0(self):
        """--hook の file_path がルート外なら出力なしで exit 0。"""
        bad = write(self.outside, "Out.swift", DEEP)
        payload = json.dumps({"tool_input": {"file_path": str(bad)}})
        self.assert_clean(run_tool(self.root, "--hook", stdin=payload))

    def test_hookのルート内違反は2で報告される(self):
        """対照: --hook でもルート内の違反は exit 2 と標準エラー。"""
        bad = write(self.root, "ProjectZD8/A.swift", DEEP)
        payload = json.dumps({"tool_input": {"file_path": str(bad)}})
        r = run_tool(self.root, "--hook", stdin=payload)
        self.assertEqual(r.code, 2)
        self.assertIn(NESTING_ERROR, r.stderr)


class LinkedBaselineTests(MetricsTestCase):
    """ベースラインの実パスがルート外を指す場合。"""

    def setUp(self):
        super().setUp()
        outside = make_root(self)
        self.target = write(outside, "outside.json", "{}\n")
        link = self.root / BASELINE_REL
        link.parent.mkdir(parents=True)
        link.symlink_to(self.target)
        self.bad = write(self.root, "ProjectZD8/A.swift", DEEP)

    def test_リンクされたベースラインでの検査は1(self):
        """外を指す baseline.json は理由を標準エラーに出して exit 1。"""
        r = run_tool(self.root, self.bad)
        self.assertEqual(r.code, 1)
        self.assertTrue(r.stderr.strip())

    def test_リンクされたベースラインは更新しない(self):
        """--update-baseline は exit 1 で、外の実体は変更されない。"""
        r = run_tool(self.root, "--update-baseline")
        self.assertEqual(r.code, 1)
        self.assertTrue(r.stderr.strip())
        self.assertEqual(self.target.read_text(encoding="utf-8"), "{}\n")
