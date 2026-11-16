"""--update-baseline の対象範囲と出力形式(README §4、§5)のテスト。"""

import json

from metrics_support import (BASELINE_REL, MetricsTestCase, make_root,
                             nested_ifs, run_tool, swift_func, write)

DEEP = swift_func(nested_ifs(4))
SHALLOW = swift_func(nested_ifs(2))


class UpdateBaselineScopeTests(MetricsTestCase):
    """記録する対象と除外する対象。"""

    def baseline_text(self):
        """責務: 書き出された baseline.json の文字列を返す。"""
        return (self.root / BASELINE_REL).read_text(encoding="utf-8")

    def test_対象4ディレクトリの超過だけを記録する(self):
        """4 ディレクトリ配下の超過は記録し、範囲外ディレクトリの超過は記録しない。"""
        for d in ("ProjectZD8", "ProjectZD8Tests", "ProjectZD8UITests",
                  "RecordingSessionLiveActivity"):
            write(self.root, d + "/Deep.swift", DEEP)
        write(self.root, "Other/Outside.swift", DEEP)
        r = run_tool(self.root, "--update-baseline")
        self.assertEqual(r.code, 0)
        text = self.baseline_text()
        for d in ("ProjectZD8/Deep.swift", "ProjectZD8Tests/Deep.swift",
                  "ProjectZD8UITests/Deep.swift",
                  "RecordingSessionLiveActivity/Deep.swift"):
            self.assertIn(d, text)
        self.assertNotIn("Outside.swift", text)

    def test_超過のないファイルは記録しない(self):
        """上限内のファイルはパスもベースラインに現れない。"""
        write(self.root, "ProjectZD8/Deep.swift", DEEP)
        write(self.root, "ProjectZD8/Ok.swift", SHALLOW)
        run_tool(self.root, "--update-baseline")
        text = self.baseline_text()
        self.assertIn("Deep.swift", text)
        self.assertNotIn("Ok.swift", text)

    def test_サブディレクトリはスラッシュ区切りで再帰する(self):
        """深い階層のファイルも `/` 区切りの相対パスで記録される。"""
        write(self.root, "ProjectZD8/Sub/Dir/Deep.swift", DEEP)
        run_tool(self.root, "--update-baseline")
        self.assertIn("ProjectZD8/Sub/Dir/Deep.swift", self.baseline_text())

    def test_ファイル単位の指標も記録する(self):
        """file_lines の超過も指標IDつきで記録される。"""
        write(self.root, "ProjectZD8/Big.swift", "// x\n" * 501)
        run_tool(self.root, "--update-baseline")
        text = self.baseline_text()
        self.assertIn("Big.swift", text)
        self.assertIn("file_lines", text)

    def test_超過があっても終了コードは0(self):
        """超過を記録する実行自体は成功扱い。"""
        write(self.root, "ProjectZD8/Deep.swift", DEEP)
        self.assertEqual(run_tool(self.root, "--update-baseline").code, 0)


class UpdateBaselineFormatTests(MetricsTestCase):
    """JSON の安定性(再実行で同一、末尾改行)。"""

    def prepare(self):
        """責務: 複数ファイルを作成順を崩して配置する。"""
        for name in ("Zeta", "Alpha", "Mid"):
            write(self.root, "ProjectZD8/%s.swift" % name, DEEP)
        write(self.root, "ProjectZD8Tests/Big.swift", "// x\n" * 501)

    def test_JSONとして読め末尾が改行(self):
        """出力は妥当な JSON で、末尾に改行がある。"""
        self.prepare()
        run_tool(self.root, "--update-baseline")
        raw = (self.root / BASELINE_REL).read_bytes()
        self.assertTrue(raw.endswith(b"\n"))
        self.assertIsNotNone(json.loads(raw.decode("utf-8")))

    def test_再実行しても同一バイト列(self):
        """入力が同じなら再実行で baseline.json は完全一致(順序固定)。"""
        self.prepare()
        run_tool(self.root, "--update-baseline")
        first = (self.root / BASELINE_REL).read_bytes()
        run_tool(self.root, "--update-baseline")
        self.assertEqual((self.root / BASELINE_REL).read_bytes(), first)

    def test_作成順が違っても同一内容(self):
        """ファイルの作成順が違う別ルートでも同じ内容になる(キー順固定)。"""
        self.prepare()
        run_tool(self.root, "--update-baseline")
        first = (self.root / BASELINE_REL).read_bytes()
        other_root = make_root(self)
        write(other_root, "ProjectZD8Tests/Big.swift", "// x\n" * 501)
        for name in ("Mid", "Alpha", "Zeta"):
            write(other_root, "ProjectZD8/%s.swift" % name, DEEP)
        run_tool(other_root, "--update-baseline")
        self.assertEqual((other_root / BASELINE_REL).read_bytes(), first)
