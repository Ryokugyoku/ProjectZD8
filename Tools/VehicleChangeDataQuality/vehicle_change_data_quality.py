#!/usr/bin/env python3
"""ProjectZD8 offline snapshotから匿名データ品質JSONを生成します。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from data_quality import build_report
from privacy_validation import validate_report


def main() -> int:
    """CLI引数を検証し、匿名JSONの生成とprivacy検査を完了します。"""

    parser = argparse.ArgumentParser(description="Build an anonymous ProjectZD8 data-quality report.")
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--scope-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    report = build_report(arguments.database, arguments.scope_manifest)
    arguments.output.write_text(
        json.dumps(report, ensure_ascii=False, allow_nan=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    validate_report(arguments.output, arguments.scope_manifest)
    print("anonymous_data_quality_report=validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

