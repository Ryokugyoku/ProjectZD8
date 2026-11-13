"""CLI引数のpathを許可した基準directory配下へ閉じ込めます。"""

from __future__ import annotations

import os
from pathlib import Path


class CLIPathError(ValueError):
    """CLI引数のpathが許可範囲外または解決不能であることを表します。"""


def resolve_root(root: Path) -> Path:
    """基準directoryを実体pathへ正規化し、存在するdirectoryであることを確認します。"""

    resolved = Path(os.path.realpath(root))
    if not resolved.is_dir():
        raise CLIPathError(f"root directory does not exist: {root}")
    return resolved


def confine_path(argument_name: str, candidate: Path, root: Path) -> Path:
    """symlinkを解決した実体pathが基準directory配下にある場合だけ返します。

    相対pathは通常のCLIと同じく作業directoryからの相対として解釈します。
    `..` やsymlinkで基準directoryの外を指すpathは拒否します。
    """

    resolved_root = resolve_root(root)
    resolved = Path(os.path.realpath(candidate))
    if os.path.commonpath([str(resolved_root), str(resolved)]) != str(resolved_root):
        raise CLIPathError(
            f"{argument_name} must be inside {resolved_root}: {candidate} resolves to {resolved}"
        )
    return resolved
