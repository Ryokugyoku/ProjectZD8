"""ベースライン(既存の超過)の読み書きと照合。

形式: {"files": {パス: {指標: 値}},
       "functions": {パス: {"関数名#出現順": {指標: 値}}}}
"""

import json
import os
from typing import Dict, Iterable, List, Optional

from .limits import BASELINE_RELATIVE_PATH
from .model import Finding, Judgement
from .safe_paths import resolve_inside


class BaselineError(Exception):
    """ベースラインファイルが読めない・形式が不正なことを表す。"""


def _function_key(finding: Finding) -> str:
    """責務: 関数単位の違反のキー `関数名#出現順` を返す。"""
    return "{}#{}".format(finding.function, finding.occurrence)


def load_baseline(root: str) -> dict:
    """責務: ルート直下の固定パスのベースラインを読む。なければ空を返す。"""
    path = resolve_inside(root, os.path.join(root, BASELINE_RELATIVE_PATH))
    if path is None:
        raise BaselineError("ベースラインの実パスがルートの外を指している")
    if not os.path.exists(path):
        return {"files": {}, "functions": {}}
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        raise BaselineError("{}: {}".format(path, error)) from error
    if not isinstance(data, dict):
        raise BaselineError("{}: 最上位がオブジェクトではない".format(path))
    return {
        "files": data.get("files") or {},
        "functions": data.get("functions") or {},
    }


def recorded_value(baseline: dict, finding: Finding) -> Optional[int]:
    """責務: 違反に対応するベースラインの記録値を返す(なければ None)。"""
    if finding.function is None:
        table = baseline["files"].get(finding.path, {})
    else:
        by_path = baseline["functions"].get(finding.path, {})
        table = by_path.get(_function_key(finding), {})
    value = table.get(finding.metric)
    return value if isinstance(value, int) else None


def judge(findings: Iterable[Finding], baseline: dict) -> List[Judgement]:
    """責務: 記録値以下の超過は許容(警告)、それ以外はエラーと判定する。"""
    result = []
    for finding in findings:
        recorded = recorded_value(baseline, finding)
        if recorded is not None and finding.value <= recorded:
            result.append(Judgement(finding, recorded))
        else:
            result.append(Judgement(finding, None))
    return result


def build_baseline(findings: Iterable[Finding]) -> dict:
    """責務: 違反の一覧からベースライン用の辞書を作る。"""
    files: Dict[str, dict] = {}
    functions: Dict[str, dict] = {}
    for finding in findings:
        if finding.function is None:
            files.setdefault(finding.path, {})[finding.metric] = finding.value
        else:
            by_path = functions.setdefault(finding.path, {})
            entry = by_path.setdefault(_function_key(finding), {})
            entry[finding.metric] = finding.value
    return {"files": files, "functions": functions}


def save_baseline(root: str, baseline: dict) -> None:
    """責務: キー順を固定し、末尾に改行を付けてルート直下の固定パスへ書く。"""
    path = resolve_inside(root, os.path.join(root, BASELINE_RELATIVE_PATH))
    if path is None:
        raise BaselineError("ベースラインの実パスがルートの外を指している")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = json.dumps(baseline, sort_keys=True, indent=2, ensure_ascii=False)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text + "\n")
