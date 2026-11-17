"""long_lines の括弧内の行番号の並べ方(README §6)のテスト。"""

from long_lines_support import expected, source_with
from metrics_support import MetricsTestCase


class LongLinesListingTests(MetricsTestCase):
    """値(超過行の数)と括弧内の行番号の並べ方。"""

    def errors_for(self, long_at, total):
        """責務: 指定行だけを長くしたソースを検査し、エラー行を返す。"""
        return self.check_swift(source_with(set(long_at), total)).errors

    def test_複数件は昇順でカンマ区切り(self):
        """値は件数、括弧内は昇順を `, ` 区切りで並べる。"""
        errs = self.errors_for([2, 4, 9], 10)
        self.assertEqual(errs, [expected("ProjectZD8/A.swift", 2, 3, "2, 4, 9")])

    def test_ちょうど5件は省略記号なし(self):
        """5 件なら `, ...` を付けない。"""
        errs = self.errors_for([1, 3, 5, 7, 9], 10)
        self.assertEqual(errs, [expected("ProjectZD8/A.swift", 1, 5, "1, 3, 5, 7, 9")])

    def test_6件は先頭5件の後に省略記号(self):
        """6 件なら値は 6、括弧内は最初の 5 件の後に `, ...`。"""
        errs = self.errors_for([2, 3, 5, 8, 13, 21], 25)
        self.assertEqual(errs, [expected("ProjectZD8/A.swift", 2, 6, "2, 3, 5, 8, 13, ...")])

    def test_多数件でも1行だけ出力し値は総数(self):
        """12 件でも出力は 1 行で、値は 12、括弧内は 5 件 + `, ...`。"""
        errs = self.errors_for(range(1, 13), 12)
        self.assertEqual(errs, [expected("ProjectZD8/A.swift", 1, 12, "1, 2, 3, 4, 5, ...")])

    def test_終了コードは1(self):
        """複数件でも終了コードは 1。"""
        r = self.check_swift(source_with({1, 2}, 3))
        self.assertEqual(r.code, 1)
