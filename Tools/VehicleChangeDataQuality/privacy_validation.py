"""匿名集計JSONへ禁止識別情報が含まれないことを検証します。"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


FORBIDDEN_KEYS = {
    "accountidentifier", "vehicleid", "sessionid", "vin", "vehiclename", "vehicledisplayidentifier",
    "acquisitiondevicename", "macimporteddeviceid", "macimporteddevicename", "manifestdigest", "payload",
}
UUID_PATTERN = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b")
LONG_HEX_PATTERN = re.compile(r"\b[0-9a-fA-F]{32,}\b")


class PrivacyValidationError(RuntimeError):
    """匿名成果物に禁止情報候補がある場合を表します。"""


def validate_report(report_path: Path, manifest_path: Path) -> None:
    """禁止key、識別子形式、manifest原値の混入を拒否します。"""

    report_text = report_path.read_text(encoding="utf-8")
    report = json.loads(report_text)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _walk(report)
    if UUID_PATTERN.search(report_text) or LONG_HEX_PATTERN.search(report_text):
        raise PrivacyValidationError("report contains an identifier-shaped value")
    for secret in _manifest_secrets(manifest):
        if secret and secret in report_text:
            raise PrivacyValidationError("report contains a private manifest value")


def _walk(value: Any) -> None:
    """JSON tree全体の禁止keyを再帰検査します。"""

    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                raise PrivacyValidationError(f"forbidden key: {key}")
            _walk(child)
    elif isinstance(value, list):
        for child in value:
            _walk(child)


def _manifest_secrets(manifest: dict[str, Any]) -> set[str]:
    """非公開manifest内の原識別値を照合集合へ抽出します。"""

    values: set[str] = set()
    for scope in manifest.get("scopes", []):
        account = scope.get("accountIdentifier")
        if isinstance(account, str):
            values.add(account)
        for vehicle in scope.get("vehicles", []):
            vehicle_id = vehicle.get("vehicleID")
            if isinstance(vehicle_id, str):
                values.add(vehicle_id)
            values.update(value for value in vehicle.get("sessionIDs", []) if isinstance(value, str))
    return values

