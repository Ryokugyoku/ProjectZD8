#!/usr/bin/env python3
"""既存の匿名データ品質JSONをprivacy契約で再検証します。"""

from __future__ import annotations

import argparse
from pathlib import Path

from privacy_validation import validate_report


def main() -> int:
    """指定JSONと非公開manifestを照合して禁止情報混入を拒否します。"""

    parser = argparse.ArgumentParser(description="Validate an anonymous ProjectZD8 report.")
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--scope-manifest", required=True, type=Path)
    arguments = parser.parse_args()
    validate_report(arguments.report, arguments.scope_manifest)
    print("privacy_validation=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

