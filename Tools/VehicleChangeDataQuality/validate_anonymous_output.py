#!/usr/bin/env python3
"""既存の匿名データ品質JSONをprivacy契約で再検証します。"""

from __future__ import annotations

import argparse
from pathlib import Path

from cli_paths import CLIPathError, confine_path
from privacy_validation import validate_report


def main(argv: list[str] | None = None) -> int:
    """指定JSONと非公開manifestを照合して禁止情報混入を拒否します。"""

    parser = argparse.ArgumentParser(description="Validate an anonymous ProjectZD8 report.")
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--scope-manifest", required=True, type=Path)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="Directory that every input path must stay inside (default: current directory).",
    )
    arguments = parser.parse_args(argv)
    try:
        report = confine_path("--report", arguments.report, arguments.root)
        scope_manifest = confine_path("--scope-manifest", arguments.scope_manifest, arguments.root)
    except CLIPathError as error:
        parser.error(str(error))
    validate_report(report, scope_manifest)
    print("privacy_validation=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

