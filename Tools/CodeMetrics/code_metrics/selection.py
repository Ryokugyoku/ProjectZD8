"""計測対象の Swift ファイルを選ぶ(明示指定・git 差分・全件走査・フック入力)。"""

import json
import os
import subprocess
from typing import Iterable, List, Optional

from .limits import BASELINE_SCAN_DIRS, SWIFT_SUFFIX
from .safe_paths import resolve_inside

_GIT_TIMEOUT_SECONDS = 30


class GitError(Exception):
    """git コマンドの失敗を表す。"""


class SelectionError(Exception):
    """引数が不正で計測対象を決められないことを表す。"""


def run_git(args: List[str], cwd: str) -> str:
    """責務: タイムアウト付きで git を実行し、標準出力を返す。"""
    try:
        done = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=_GIT_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GitError("git {}: {}".format(" ".join(args), error)) from error
    if done.returncode != 0:
        message = done.stderr.strip() or "終了コード {}".format(done.returncode)
        raise GitError("git {}: {}".format(" ".join(args), message))
    return done.stdout


def find_root(cwd: str) -> str:
    """責務: git のトップレベル、なければ cwd をリポジトリのルートとする。"""
    try:
        top = run_git(["rev-parse", "--show-toplevel"], cwd).strip()
    except GitError:
        return os.path.realpath(cwd)
    return os.path.realpath(top) if top else os.path.realpath(cwd)


def _relative(path: str, root: str, base: str) -> Optional[str]:
    """責務: ルート配下のパスを `/` 区切りの相対パスにする(外なら None)。"""
    absolute = path if os.path.isabs(path) else os.path.join(base, path)
    inside = resolve_inside(root, absolute)
    if inside is None:
        return None
    return os.path.relpath(inside, os.path.realpath(root)).replace(os.sep, "/")


def filter_swift(paths: Iterable[str], root: str, base: str) -> List[str]:
    """責務: 存在する .swift だけを、重複なく整列した相対パスで返す。"""
    result = set()
    for path in paths:
        if not path.endswith(SWIFT_SUFFIX):
            continue
        rel = _relative(path, root, base)
        if rel is not None and os.path.isfile(os.path.join(root, rel)):
            result.add(rel)
    return sorted(result)


def resolve_commit(root: str, ref: str) -> str:
    """責務: REF を検証してコミットの SHA にする(`-` 始まりは拒否)。"""
    if ref.startswith("-"):
        raise SelectionError("--changed-since の REF が `-` で始まっている: " + ref)
    args = ["rev-parse", "--verify", "--end-of-options", ref + "^{commit}"]
    return run_git(args, root).strip()


def changed_paths(root: str, ref: str) -> List[str]:
    """責務: REF...HEAD の差分と未コミット変更のパスを集める。"""
    sha = resolve_commit(root, ref)
    committed = run_git(
        ["diff", "--name-only", "--diff-filter=ACMR", sha + "...HEAD", "--"],
        root,
    )
    working = run_git(["diff", "--name-only", "HEAD", "--"], root)
    return (committed + "\n" + working).splitlines()


def scan_all(root: str) -> List[str]:
    """責務: ベースライン対象ディレクトリ配下の全 .swift を集める。"""
    found = []
    for name in BASELINE_SCAN_DIRS:
        for folder, _dirs, files in os.walk(os.path.join(root, name)):
            found.extend(
                os.path.join(folder, f)
                for f in files
                if f.endswith(SWIFT_SUFFIX)
            )
    return found


def hook_path(raw: str) -> Optional[str]:
    """責務: フックの標準入力 JSON から対象ファイルのパスを取り出す。"""
    try:
        data = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    for section, key in (("tool_input", "file_path"),
                         ("tool_response", "filePath")):
        value = (data.get(section) or {}).get(key) if isinstance(
            data.get(section), dict) else None
        if isinstance(value, str) and value:
            return value
    return None
