"""ルートの外を指すパスを弾く(シンボリックリンクは実パスで判定する)。"""

import os
from typing import Optional


def resolve_inside(root: str, path: str) -> Optional[str]:
    """責務: path の実パスがルートの実パスの配下なら実パスを、外なら None を返す。"""
    real_root = os.path.realpath(root)
    real_path = os.path.realpath(path)
    try:
        common = os.path.commonpath([real_root, real_path])
    except ValueError:
        return None
    return real_path if common == real_root else None
