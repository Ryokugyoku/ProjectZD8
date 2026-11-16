#!/usr/bin/env python3
"""Swift の複雑さチェックの入口。使い方は README.md を参照。"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from code_metrics.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
