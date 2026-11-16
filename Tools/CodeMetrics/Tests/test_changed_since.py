"""--changed-since(README §5)のテスト。実際の git リポジトリで検証する。"""

import subprocess

from metrics_support import (MetricsTestCase, nested_ifs, run_tool,
                             swift_func, write)

DEEP = swift_func(nested_ifs(4))
OK = swift_func("work()")


class ChangedSinceTests(MetricsTestCase):
    """REF 以降のコミット済み変更と未コミット変更を対象にする。"""

    def git(self, *args):
        """責務: 作成者設定つきで git を実行し標準出力を返す(タイムアウト付き)。"""
        cmd = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com",
               "-c", "commit.gpgsign=false"] + list(args)
        done = subprocess.run(cmd, cwd=str(self.root), timeout=60, check=True,
                              capture_output=True, text=True)
        return done.stdout.strip()

    def commit_all(self, message):
        """責務: 全変更をコミットして先頭コミットの ID を返す。"""
        self.git("add", "-A")
        self.git("commit", "-m", message)
        return self.git("rev-parse", "HEAD")

    def setUp(self):
        super().setUp()
        self.git("init")
        write(self.root, "Old.swift", DEEP)
        write(self.root, "Clean.swift", OK)
        self.base = self.commit_all("base")

    def test_REF以降にコミットした違反を報告(self):
        """REF より後のコミットで追加した違反ファイルだけが対象。既存の Old は対象外。"""
        write(self.root, "New.swift", DEEP)
        self.commit_all("add new")
        r = run_tool(self.root, "--changed-since", self.base)
        self.assertEqual(r.errors, ["New.swift:1: error: nesting 4 > 3 (f)"])
        self.assertEqual(r.code, 1)

    def test_未コミットの変更も対象(self):
        """作業ツリーの未コミット変更(追跡済みファイル)も検査される。"""
        write(self.root, "Clean.swift", DEEP)
        r = run_tool(self.root, "--changed-since", self.base)
        self.assertEqual(r.errors, ["Clean.swift:1: error: nesting 4 > 3 (f)"])

    def test_コミット済みと未コミットの合算(self):
        """コミット済みの New と未コミットの Clean の両方を、パス順で報告。"""
        write(self.root, "New.swift", DEEP)
        self.commit_all("add new")
        write(self.root, "Clean.swift", DEEP)
        r = run_tool(self.root, "--changed-since", self.base)
        self.assertEqual(r.errors, [
            "Clean.swift:1: error: nesting 4 > 3 (f)",
            "New.swift:1: error: nesting 4 > 3 (f)"])

    def test_変更のないリポジトリは成功(self):
        """REF=HEAD で変更なしなら対象 0 件で exit 0。"""
        self.assert_clean(run_tool(self.root, "--changed-since", "HEAD"))

    def test_削除されたファイルは無視(self):
        """未コミットで削除した違反ファイルは存在しないので飛ばされ exit 0。"""
        (self.root / "Old.swift").unlink()
        self.assert_clean(run_tool(self.root, "--changed-since", self.base))

    def test_swift以外の変更は対象外(self):
        """変更された .swift 以外は検査されない。"""
        write(self.root, "notes.txt", "// x\n" * 600)
        self.commit_all("txt")
        self.assert_clean(run_tool(self.root, "--changed-since", self.base))
