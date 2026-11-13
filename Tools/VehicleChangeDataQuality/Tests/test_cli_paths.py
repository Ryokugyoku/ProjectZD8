"""CLI引数pathの基準directory閉じ込めを検証します。"""

from __future__ import annotations

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

import validate_anonymous_output
import vehicle_change_data_quality
from cli_paths import CLIPathError, confine_path


class ConfinePathTests(unittest.TestCase):
    """基準directory内外のpathとsymlinkの扱いを固定します。"""

    def setUp(self) -> None:
        """基準directoryとその外側directoryを一時領域に用意します。"""

        self._temporary = tempfile.TemporaryDirectory()
        base = Path(os.path.realpath(self._temporary.name))
        self.root = base / "root"
        self.outside = base / "outside"
        self.root.mkdir()
        self.outside.mkdir()

    def tearDown(self) -> None:
        """一時領域を削除します。"""

        self._temporary.cleanup()

    def test_accepts_existing_and_new_paths_inside_root(self) -> None:
        """基準directory配下の既存fileと未作成fileを実体pathで返します。"""

        existing = self.root / "input.json"
        existing.write_text("{}", encoding="utf-8")
        self.assertEqual(confine_path("--database", existing, self.root), existing)
        nested = self.root / "nested" / "output.json"
        self.assertEqual(confine_path("--output", nested, self.root), nested)

    def test_resolves_relative_paths_from_working_directory(self) -> None:
        """相対pathを作業directory基準で解決し、基準directory内なら通します。"""

        previous = Path.cwd()
        os.chdir(self.root)
        try:
            self.assertEqual(confine_path("--output", Path("out.json"), Path(".")), self.root / "out.json")
        finally:
            os.chdir(previous)

    def test_rejects_parent_traversal(self) -> None:
        """`..` で基準directoryの外へ出るpathを拒否します。"""

        with self.assertRaises(CLIPathError):
            confine_path("--output", self.root / ".." / "outside" / "out.json", self.root)

    def test_rejects_absolute_path_outside_root(self) -> None:
        """基準directory外の絶対pathを拒否します。"""

        with self.assertRaises(CLIPathError):
            confine_path("--database", self.outside / "db.sqlite", self.root)

    def test_rejects_sibling_with_shared_prefix(self) -> None:
        """文字列prefixだけ一致する兄弟directoryを配下とみなしません。"""

        sibling = self.root.parent / "root-sibling"
        sibling.mkdir()
        with self.assertRaises(CLIPathError):
            confine_path("--output", sibling / "out.json", self.root)

    def test_rejects_symlinked_file_pointing_outside(self) -> None:
        """基準directory内のsymlinkが外部fileを指す場合を拒否します。"""

        target = self.outside / "secret.json"
        target.write_text("{}", encoding="utf-8")
        link = self.root / "link.json"
        link.symlink_to(target)
        with self.assertRaises(CLIPathError):
            confine_path("--scope-manifest", link, self.root)

    def test_rejects_new_file_under_symlinked_directory_pointing_outside(self) -> None:
        """外部directoryを指すsymlink配下への新規出力を拒否します。"""

        link = self.root / "escape"
        link.symlink_to(self.outside, target_is_directory=True)
        with self.assertRaises(CLIPathError):
            confine_path("--output", link / "out.json", self.root)

    def test_rejects_missing_root(self) -> None:
        """存在しない基準directoryを拒否します。"""

        with self.assertRaises(CLIPathError):
            confine_path("--output", self.root / "out.json", self.root / "missing")


class CLIPathRejectionTests(unittest.TestCase):
    """CLIが範囲外pathで書き込み前に分かりやすく終了することを検証します。"""

    def test_report_cli_rejects_output_outside_root_without_writing(self) -> None:
        """範囲外 `--output` をusage errorで拒否し、fileを作成しません。"""

        with tempfile.TemporaryDirectory() as directory:
            base = Path(os.path.realpath(directory))
            root = base / "root"
            root.mkdir()
            escaped = base / "escaped.json"
            stderr = io.StringIO()
            with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
                vehicle_change_data_quality.main([
                    "--root", str(root),
                    "--database", str(root / "db.sqlite"),
                    "--scope-manifest", str(root / "scope.json"),
                    "--output", str(root / ".." / "escaped.json"),
                ])
            self.assertEqual(raised.exception.code, 2)
            self.assertIn("--output must be inside", stderr.getvalue())
            self.assertFalse(escaped.exists())

    def test_validate_cli_rejects_manifest_outside_root(self) -> None:
        """範囲外 `--scope-manifest` をusage errorで拒否します。"""

        with tempfile.TemporaryDirectory() as directory:
            base = Path(os.path.realpath(directory))
            root = base / "root"
            root.mkdir()
            stderr = io.StringIO()
            with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
                validate_anonymous_output.main([
                    "--root", str(root),
                    "--report", str(root / "report.json"),
                    "--scope-manifest", str(base / "scope.json"),
                ])
            self.assertEqual(raised.exception.code, 2)
            self.assertIn("--scope-manifest must be inside", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
