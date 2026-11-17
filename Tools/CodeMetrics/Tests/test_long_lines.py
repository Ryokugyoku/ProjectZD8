"""long_lines(README §3.1、§6)の数え方と出力形式のテスト。"""

from long_lines_support import (LIMIT, SHORT, expected, line_of,
                                source_with)
from metrics_support import MetricsTestCase


class LongLinesBoundaryTests(MetricsTestCase):
    """160 文字と 161 文字の境界、数え方の細部。"""

    def test_160文字ちょうどは違反でない(self):
        """160 文字の行は数えず、出力なし・終了コード 0。"""
        self.assert_clean(self.check_swift(line_of(LIMIT) + "\n"))

    def test_161文字は1件のエラー(self):
        """161 文字の行は値 1 のエラーで終了コード 1。"""
        r = self.check_swift(line_of(LIMIT + 1) + "\n")
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 1, 1, "1")])
        self.assertEqual(r.code, 1)

    def test_行番号は最初の超過行(self):
        """3 行目だけが長ければ行番号は 3、括弧内も 3。"""
        r = self.check_swift(source_with({3}, 5))
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 3, 1, "3")])

    def test_160と161が混在すると161の行だけ数える(self):
        """160 文字の行と 161 文字の行が1つずつなら値は 1、行は 161 の方。"""
        text = line_of(LIMIT) + "\n" + line_of(LIMIT + 1) + "\n"
        r = self.check_swift(text)
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 2, 1, "2")])

    def test_日本語は1文字を1と数える_160は違反でない(self):
        """日本語 160 文字(UTF-8 では 480 バイト)の行は違反でない。"""
        self.assert_clean(self.check_swift("//" + "あ" * (LIMIT - 2) + "\n"))

    def test_日本語161文字は違反(self):
        """日本語 161 文字の行は違反になる。"""
        r = self.check_swift("//" + "あ" * (LIMIT - 1) + "\n")
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 1, 1, "1")])

    def test_タブは1文字_160は違反でない(self):
        """タブ 160 個の行は違反でない。"""
        self.assert_clean(self.check_swift("\t" * LIMIT + "\n"))

    def test_タブ161個は違反(self):
        """タブ 161 個の行は違反になる。"""
        r = self.check_swift("\t" * (LIMIT + 1) + "\n")
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 1, 1, "1")])

    def test_CRLFの復帰は数えない_160は違反でない(self):
        """160 文字 + CRLF の行は違反でない(\\r を文字数に入れない)。"""
        self.assert_clean(self.check_swift(line_of(LIMIT) + "\r\n" + SHORT + "\r\n"))

    def test_CRLFで161文字は違反(self):
        """161 文字 + CRLF の 2 行目は違反として行番号 2 で出る。"""
        r = self.check_swift(SHORT + "\r\n" + line_of(LIMIT + 1) + "\r\n")
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 2, 1, "2")])

    def test_末尾に改行のない最終行も数える(self):
        """改行なしで終わる 161 文字の最終行は違反として数える。"""
        r = self.check_swift(SHORT + "\n" + line_of(LIMIT + 1))
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 2, 1, "2")])

    def test_末尾に改行のない160文字の最終行は違反でない(self):
        """改行なしで終わる 160 文字の最終行は違反でない。"""
        self.assert_clean(self.check_swift(SHORT + "\n" + line_of(LIMIT)))

    def test_コメント行も数える(self):
        """// コメントだけの 161 文字の行も違反。"""
        r = self.check_swift(line_of(LIMIT + 1, "// ") + "\n")
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 1, 1, "1")])

    def test_文字列リテラル内も数える(self):
        """文字列リテラルで 161 文字になる行も違反。"""
        head = 'let s = "'
        text = head + "x" * (LIMIT + 1 - len(head) - 1) + '"\n'
        self.assertEqual(len(text), LIMIT + 2)
        r = self.check_swift(text)
        self.assertEqual(r.errors, [expected("ProjectZD8/A.swift", 1, 1, "1")])
