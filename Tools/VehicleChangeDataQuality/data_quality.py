"""読み取り専用SQLite snapshotを匿名データ品質JSONへ変換します。"""

from __future__ import annotations

import json
import math
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from formula_evaluator import PIDDefinition, classify


EXPECTED_COLUMNS = {
    "connection_sessions": (
        "id", "accountIdentifier", "startedAt", "endedAt", "endReason", "stopReviewDecision",
        "vehicleID", "vehicleName", "vehicleDisplayIdentifier", "acquisitionPlatform",
        "acquisitionDeviceName", "startingOdometerKilometers", "endingOdometerKilometers",
        "distanceSourceModelCode", "rawRecordCount", "rawByteCount", "localRawState",
        "cloudSyncState", "manifestDigest", "macImportedDeviceID", "macImportedDeviceName",
        "macImportedAt", "macImportedManifestDigest", "rawLastAccessedAt",
    ),
    "connection_session_raw_logs": (
        "sessionID", "sequence", "observedAt", "batchElapsedNanoseconds", "service", "pid", "payload",
    ),
    "obd_pid_definitions": (
        "service", "pid", "header", "vehicleModelCode", "nameKey", "requiredByteCount", "formula",
        "unit", "minimumValue", "maximumValue", "sourceURI", "revision", "summaryKey", "highValueKey",
        "lowValueKey", "correlationKey",
    ),
}

DECODE_CLASSES = (
    "numericFinite", "missingDefinition", "unavailableFormula", "insufficientBytes",
    "invalidExpression", "nonFinite", "outOfDeclaredRange",
)


class DataQualityError(RuntimeError):
    """snapshotを安全に集計できない場合を表します。"""


def open_readonly(database_path: Path) -> sqlite3.Connection:
    """SQLiteをURI read-onlyかつquery-onlyで開きます。"""

    absolute_path = database_path.resolve(strict=True)
    uri = f"file:{quote(str(absolute_path), safe='/')}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    connection.execute("PRAGMA trusted_schema = OFF")
    return connection


def build_report(database_path: Path, manifest_path: Path) -> dict[str, Any]:
    """検証済みscopeだけを匿名データ品質報告へ集計します。"""

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    scopes = manifest.get("scopes")
    if manifest.get("inputKind") != "physicalDeviceSnapshot" or not isinstance(scopes, list) or not scopes:
        raise DataQualityError("manifest must describe a physical device snapshot")
    connection = open_readonly(database_path)
    try:
        preflight = _preflight(connection)
        reports = []
        classification_totals: Counter[str] = Counter()
        for account_index, scope in enumerate(scopes, start=1):
            account_identifier = _required_string(scope, "accountIdentifier")
            vehicle_reports = []
            vehicles = scope.get("vehicles")
            if not isinstance(vehicles, list) or not vehicles:
                raise DataQualityError("each scope must contain vehicles")
            for vehicle_index, vehicle in enumerate(vehicles, start=1):
                vehicle_id = _required_string(vehicle, "vehicleID")
                classification = _required_string(vehicle, "classification")
                if classification not in {"realVehicle", "demo", "fixture", "indeterminate"}:
                    raise DataQualityError("unsupported session classification")
                session_ids = vehicle.get("sessionIDs")
                if not isinstance(session_ids, list) or not session_ids or not all(isinstance(value, str) for value in session_ids):
                    raise DataQualityError("each vehicle must contain explicit session IDs")
                classification_totals[classification] += len(session_ids)
                vehicle_reports.append(
                    _build_vehicle_report(
                        connection,
                        account_identifier,
                        vehicle_id,
                        session_ids,
                        classification,
                        f"V{vehicle_index:03d}",
                    )
                )
            reports.append({"accountLabel": f"A{account_index:03d}", "vehicles": vehicle_reports})
        return {
            "calculationVersion": 1,
            "classificationTotals": dict(sorted(classification_totals.items())),
            "contractVersion": 1,
            "evidenceBoundary": "anonymousOfflineAggregateOnly",
            "inputKind": "physicalDeviceSnapshot",
            "percentileMethod": "hyndmanFanType7",
            "preflight": preflight,
            "schemaContractVersion": 1,
            "scopes": reports,
            "status": "accepted",
            "exclusions": {},
            "warnings": [
                "PID revisions are snapshot revisions, not acquisition-time revisions.",
                "Cloud uploaded state does not prove Production Asset availability or restoration.",
                "Raw sequence is persistence order, not response arrival order.",
            ],
        }
    finally:
        connection.close()


def percentile(values: Iterable[float], probability: float) -> float | None:
    """Hyndman-Fan type 7 percentileを返します。"""

    ordered = sorted(float(value) for value in values)
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def distribution(values: Iterable[float]) -> dict[str, float | int | None]:
    """数値列を固定percentile集合へ要約します。"""

    materialized = [float(value) for value in values]
    if not materialized:
        return {key: None for key in ("min", "p10", "median", "p90", "p95", "p99", "max", "iqr")} | {"count": 0}
    p25 = percentile(materialized, 0.25)
    p75 = percentile(materialized, 0.75)
    return {
        "count": len(materialized),
        "iqr": _rounded(p75 - p25 if p25 is not None and p75 is not None else None),
        "max": _rounded(max(materialized)),
        "median": _rounded(percentile(materialized, 0.5)),
        "min": _rounded(min(materialized)),
        "p10": _rounded(percentile(materialized, 0.1)),
        "p90": _rounded(percentile(materialized, 0.9)),
        "p95": _rounded(percentile(materialized, 0.95)),
        "p99": _rounded(percentile(materialized, 0.99)),
    }


def _preflight(connection: sqlite3.Connection) -> dict[str, Any]:
    """integrity、schema、主従整合性を集計前に検証します。"""

    integrity_rows = [row[0] for row in connection.execute("PRAGMA integrity_check")]
    if integrity_rows != ["ok"]:
        raise DataQualityError("integrity_check failed")
    for table, expected in EXPECTED_COLUMNS.items():
        actual = tuple(row[1] for row in connection.execute(f"PRAGMA table_info({table})"))
        if actual != expected:
            raise DataQualityError(f"schema mismatch for {table}")
    orphan_raw = connection.execute(
        "SELECT COUNT(*) FROM connection_session_raw_logs AS raw "
        "LEFT JOIN connection_sessions AS session ON session.id = raw.sessionID WHERE session.id IS NULL"
    ).fetchone()[0]
    duplicate_sequence = connection.execute(
        "SELECT COUNT(*) FROM (SELECT sessionID, sequence, COUNT(*) AS count FROM connection_session_raw_logs "
        "GROUP BY sessionID, sequence HAVING count > 1)"
    ).fetchone()[0]
    return {
        "duplicateSequenceGroups": duplicate_sequence,
        "integrityCheck": "ok",
        "orphanRawRows": orphan_raw,
        "schemaCompatible": True,
    }


def _build_vehicle_report(
    connection: sqlite3.Connection,
    account_identifier: str,
    vehicle_id: str,
    session_ids: list[str],
    classification: str,
    vehicle_label: str,
) -> dict[str, Any]:
    """1つのaccount/vehicle/session scopeを匿名集計します。"""

    placeholders = ",".join("?" for _ in session_ids)
    session_sql = (
        "SELECT id, startedAt, endedAt, endReason, stopReviewDecision, acquisitionPlatform, "
        "startingOdometerKilometers, endingOdometerKilometers, rawRecordCount, rawByteCount, "
        "localRawState, cloudSyncState, manifestDigest "
        f"FROM connection_sessions WHERE accountIdentifier = ? AND vehicleID = ? AND id IN ({placeholders}) "
        "ORDER BY startedAt, id"
    )
    sessions = list(connection.execute(session_sql, [account_identifier, vehicle_id, *session_ids]))
    if len(sessions) != len(set(session_ids)):
        raise DataQualityError("scope manifest does not match stored sessions")
    session_id_set = {row["id"] for row in sessions}
    if session_id_set != set(session_ids):
        raise DataQualityError("scope manifest contains a wrong account or vehicle session")
    definitions = _definitions(connection)
    raw_sql = (
        "SELECT sessionID, sequence, observedAt, batchElapsedNanoseconds, service, pid, payload "
        f"FROM connection_session_raw_logs WHERE sessionID IN ({placeholders}) "
        "ORDER BY sessionID, sequence"
    )
    raw_rows = list(connection.execute(raw_sql, session_ids))
    raw_by_session: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in raw_rows:
        raw_by_session[row["sessionID"]].append(row)

    started = [_parse_timestamp(row["startedAt"]) for row in sessions]
    ended = [_parse_timestamp(row["endedAt"]) for row in sessions if row["endedAt"] is not None]
    raw_times = [_parse_timestamp(row["observedAt"]) for row in raw_rows]
    session_durations = [
        (_parse_timestamp(row["endedAt"]) - _parse_timestamp(row["startedAt"])).total_seconds()
        for row in sessions if row["endedAt"] is not None
    ]
    raw_durations = []
    duration_differences = []
    samples_per_session = []
    sequence_gap_sessions = 0
    summary_count_mismatch = 0
    summary_byte_mismatch = 0
    for session in sessions:
        rows = raw_by_session.get(session["id"], [])
        samples_per_session.append(len(rows))
        sequences = [row["sequence"] for row in rows]
        if sequences != list(range(len(rows))):
            sequence_gap_sessions += 1
        if session["rawRecordCount"] != len(rows):
            summary_count_mismatch += 1
        payload_bytes = sum(len(row["payload"]) for row in rows)
        if session["rawByteCount"] != payload_bytes:
            summary_byte_mismatch += 1
        if rows:
            observed = [_parse_timestamp(row["observedAt"]) for row in rows]
            raw_duration = (max(observed) - min(observed)).total_seconds()
            raw_durations.append(raw_duration)
            if session["endedAt"] is not None:
                duration_differences.append(
                    (_parse_timestamp(session["endedAt"]) - _parse_timestamp(session["startedAt"])).total_seconds()
                    - raw_duration
                )

    distance_values = []
    distance_failed = 0
    for row in sessions:
        start = row["startingOdometerKilometers"]
        end = row["endingOdometerKilometers"]
        if start is None or end is None or not math.isfinite(start) or not math.isfinite(end) or start < 0 or end < start:
            distance_failed += 1
        else:
            distance_values.append(end - start)

    pid_rows: dict[tuple[int, int], list[sqlite3.Row]] = defaultdict(list)
    for row in raw_rows:
        pid_rows[(row["service"], row["pid"])].append(row)
    pid_reports = [
        _build_pid_report(key, rows, definitions.get(key), len(sessions), len({time.date() for time in raw_times}))
        for key, rows in sorted(pid_rows.items())
    ]

    return {
        "classification": classification,
        "classificationDistribution": {classification: len(sessions)},
        "cloudStateDistribution": _counter(row["cloudSyncState"] for row in sessions),
        "distance": {
            "establishedCount": len(distance_values),
            "failedCount": distance_failed,
            "totalKilometers": _rounded(sum(distance_values)),
        },
        "durationDifferenceSeconds": distribution(duration_differences),
        "endReasonDistribution": _counter(row["endReason"] or "active" for row in sessions),
        "localStateDistribution": _counter(row["localRawState"] for row in sessions),
        "manifestPresenceDistribution": _counter("present" if row["manifestDigest"] else "absent" for row in sessions),
        "observationEndDate": max(raw_times).date().isoformat() if raw_times else None,
        "observationStartDate": min(raw_times).date().isoformat() if raw_times else None,
        "pids": pid_reports,
        "platformDistribution": _counter(row["acquisitionPlatform"] or "unknown" for row in sessions),
        "qualityChecks": {
            "rawSummaryByteMismatchSessions": summary_byte_mismatch,
            "rawSummaryCountMismatchSessions": summary_count_mismatch,
            "sequenceGapSessions": sequence_gap_sessions,
        },
        "rawPayloadByteCount": sum(len(row["payload"]) for row in raw_rows),
        "rawLogCount": len(raw_rows),
        "rawObservationDurationSeconds": {"distribution": distribution(raw_durations), "total": _rounded(sum(raw_durations))},
        "rawAvailabilityDistribution": _raw_availability(sessions, raw_by_session),
        "recordedDayCount": len({time.date() for time in raw_times}),
        "reviewDecisionDistribution": _counter(row["stopReviewDecision"] or "unreviewed" for row in sessions),
        "samplesPerSession": distribution(samples_per_session),
        "sessionCount": len(sessions),
        "sessionStatusDistribution": _counter(_session_status(row) for row in sessions),
        "sessionDurationSeconds": {"distribution": distribution(session_durations), "total": _rounded(sum(session_durations))},
        "sessionEndDate": max(ended).date().isoformat() if ended else None,
        "sessionStartDate": min(started).date().isoformat() if started else None,
        "vehicleLabel": vehicle_label,
        "learningEligibility": {
            "status": "notEstablished",
            "reasons": ["acquisitionRevisionUnavailable", "operatingConditionCoverageNotEvaluated"],
        },
    }


def _session_status(session: sqlite3.Row) -> str:
    """終了原因とreview結果をDomain表示状態へ変換します。"""

    if session["endReason"] is None:
        return "connected"
    if session["endReason"] == "userDisconnected" or session["stopReviewDecision"] == "userInitiated":
        return "completed"
    return "interrupted"


def _definitions(connection: sqlite3.Connection) -> dict[tuple[int, int], PIDDefinition]:
    """snapshot内PID定義をService/PID索引へ変換します。"""

    rows = connection.execute(
        "SELECT service, pid, requiredByteCount, formula, minimumValue, maximumValue, revision "
        "FROM obd_pid_definitions ORDER BY service, pid"
    )
    return {
        (row["service"], row["pid"]): PIDDefinition(
            service=row["service"], pid=row["pid"], required_byte_count=row["requiredByteCount"],
            formula=row["formula"], minimum_value=row["minimumValue"], maximum_value=row["maximumValue"],
            revision=row["revision"],
        )
        for row in rows
    }


def _build_pid_report(
    key: tuple[int, int],
    rows: list[sqlite3.Row],
    definition: PIDDefinition | None,
    session_count: int,
    recorded_day_count: int,
) -> dict[str, Any]:
    """1つのService/PIDを件数、変換、間隔へ集計します。"""

    decode_counts = Counter({name: 0 for name in DECODE_CLASSES})
    times_by_session: dict[str, list[datetime]] = defaultdict(list)
    observed_days = set()
    for row in rows:
        decode_counts[classify(definition, bytes(row["payload"]))] += 1
        observed_at = _parse_timestamp(row["observedAt"])
        times_by_session[row["sessionID"]].append(observed_at)
        observed_days.add(observed_at.date())
    intervals = []
    for times in times_by_session.values():
        ordered = sorted(times)
        intervals.extend((right - left).total_seconds() for left, right in zip(ordered, ordered[1:]))
    median_interval = percentile(intervals, 0.5)
    thresholds = {
        "over10Seconds": 10.0,
        "over30Seconds": 30.0,
        "over60Seconds": 60.0,
        "over3xMedian": 3.0 * median_interval if median_interval is not None else None,
        "over5xMedian": 5.0 * median_interval if median_interval is not None else None,
        "overMax10SecondsOr3xMedian": max(10.0, 3.0 * median_interval) if median_interval is not None else None,
    }
    return {
        "batchElapsedMilliseconds": distribution(row["batchElapsedNanoseconds"] / 1_000_000 for row in rows),
        "decodeCounts": dict(decode_counts),
        "definitionRevision": definition.revision if definition else None,
        "intervalSeconds": distribution(intervals),
        "longGapCounts": {
            name: sum(1 for value in intervals if threshold is not None and value > threshold)
            for name, threshold in thresholds.items()
        },
        "observationCount": len(rows),
        "observedDayRate": _rounded(len(observed_days) / recorded_day_count) if recorded_day_count else None,
        "observedDayRateDenominator": recorded_day_count,
        "observedSessionRate": _rounded(len(times_by_session) / session_count) if session_count else None,
        "observedSessionRateDenominator": session_count,
        "pid": key[1],
        "revisionMeaning": "reanalyzedWithSnapshotRevision" if definition else "missingDefinition",
        "service": key[0],
    }


def _raw_availability(sessions: list[sqlite3.Row], raw_by_session: dict[str, list[sqlite3.Row]]) -> dict[str, int]:
    """sessionをローカル、復元候補、利用不能へ排他分類します。"""

    result: Counter[str] = Counter()
    for row in sessions:
        actual_count = len(raw_by_session.get(row["id"], []))
        if row["localRawState"] == "available" and actual_count > 0 and row["rawRecordCount"] == actual_count:
            result["localAvailable"] += 1
        elif row["localRawState"] == "removed" and actual_count == 0 and row["cloudSyncState"] == "uploaded" and row["manifestDigest"]:
            result["cloudRestoreCandidate"] += 1
        else:
            result["unavailable"] += 1
    return dict(result)


def _counter(values: Iterable[str]) -> dict[str, int]:
    """カテゴリ値を安定順の件数辞書へ変換します。"""

    return dict(sorted(Counter(values).items()))


def _parse_timestamp(value: str) -> datetime:
    """GRDBのISO 8601日時をtimezone付きdatetimeへ変換します。"""

    if not isinstance(value, str):
        raise DataQualityError("timestamp must be stored as text")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise DataQualityError("invalid timestamp") from error
    if parsed.tzinfo is None:
        # GRDB Date.databaseValue stores `yyyy-MM-dd HH:mm:ss.SSS` in UTC.
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _required_string(mapping: dict[str, Any], key: str) -> str:
    """manifestの必須非空文字列を検証します。"""

    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise DataQualityError(f"manifest key {key} must be a non-empty string")
    return value


def _rounded(value: float | None) -> float | None:
    """匿名集計数値を再現可能な小数精度へ丸めます。"""

    return None if value is None else round(float(value), 6)
