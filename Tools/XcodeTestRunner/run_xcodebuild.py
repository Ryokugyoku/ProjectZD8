#!/usr/bin/env python3
"""xcodebuild を直列・時間上限つきで走らせるラッパーの入口。使い方は README.md を参照。"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from xcode_test_runner.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
