"""読み取り専用SQLite snapshot(insight-v1.sqlite)を匿名データ品質JSONへ変換します。"""

from __future__ import annotations

import json
import math
import sqlite3
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from formula_evaluator import PIDDefinition, classify


CALCULATION_VERSION = 2
CONTRACT_VERSION = 2
SCHEMA_CONTRACT_VERSION = 2
SOURCE_SCHEMA = "insight-v1"
EXPECTED_MIGRATIONS = ["v1"]

EXPECTED_COLUMNS = {
    "sessions": (
        "id", "vehicleID", "startedAt", "endedAt", "endReason", "isDemo", "adapterName",
        "adapterTransport", "platform", "deviceID", "deviceName", "appVersion", "appBuild",
        "pollingPolicyVersion", "odometerStartKilometers", "odometerEndKilometers", "distanceSource",
        "sampleCount", "respondedCount", "payloadByteCount", "rawAvailability", "archiveDigest",
        "modifiedAt", "deletedAt",
    ),
    "session_pids": (
        "sessionID", "ordinal", "service", "pid", "header", "support", "isCollectionEnabled",
        "isFastGroup", "definitionRevision", "requiredByteCount", "formula", "unit", "minimumValue",
        "maximumValue",
    ),
    "session_samples": (
        "sessionID", "sequence", "tick", "elapsedMicroseconds", "service", "pid", "outcome", "payload",
    ),
}

# Domain `SampleOutcome.rawValue` と一致させます。
OUTCOME_NAMES = {0: "responded", 1: "noData", 2: "timedOut", 3: "failed"}
CLASSIFICATIONS = {"realVehicle", "demo", "fixture", "indeterminate"}

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
    """検証済みscopeだけを匿名データ品質報告へ集計します。

    manifestは `{"inputKind": "physicalDeviceSnapshot", "vehicles": [{"vehicleID", "classification", "sessionIDs"}]}`。
    アカウント識別子は存在しません(データは端末のiCloudアカウントに属する)。
    """

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    vehicles = manifest.get("vehicles")
    if manifest.get("inputKind") != "physicalDeviceSnapshot" or not isinstance(vehicles, list) or not vehicles:
        raise DataQualityError("manifest must describe a physical device snapshot with vehicles")
    connection = open_readonly(database_path)
    try:
        preflight = _preflight(connection)
        vehicle_reports = []
        classification_totals: Counter[str] = Counter()
        excluded_demo = 0
        for vehicle_index, vehicle in enumerate(vehicles, start=1):
            vehicle_id = _required_string(vehicle, "vehicleID")
            classification = _required_string(vehicle, "classification")
            if classification not in CLASSIFICATIONS:
                raise DataQualityError("unsupported session classification")
            session_ids = vehicle.get("sessionIDs")
            if not isinstance(session_ids, list) or not session_ids or not all(isinstance(value, str) for value in session_ids):
                raise DataQualityError("each vehicle must contain explicit session IDs")
            report, excluded = _build_vehicle_report(
                connection, vehicle_id, session_ids, classification, f"V{vehicle_index:03d}",
            )
            classification_totals[classification] += report["sessionCount"]
            excluded_demo += excluded
            vehicle_reports.append(report)
        return {
            "calculationVersion": CALCULATION_VERSION,
            "classificationTotals": dict(sorted(classification_totals.items())),
            "contractVersion": CONTRACT_VERSION,
            "evidenceBoundary": "anonymousOfflineAggregateOnly",
            "exclusions": {"demoSessionsWithoutDemoClassification": excluded_demo},
            "inputKind": "physicalDeviceSnapshot",
            "percentileMethod": "hyndmanFanType7",
            "preflight": preflight,
            "schemaContractVersion": SCHEMA_CONTRACT_VERSION,
            "sourceSchema": SOURCE_SCHEMA,
            "status": "accepted",
            "vehicles": vehicle_reports,
            "warnings": [
                "Sample wall-clock times are session start plus monotonic elapsed time, not device clock readings.",
                "Raw availability cloudOnly sessions carry no local samples and cannot be analysed offline.",
                "Rates are per request row; sessions that never requested a PID do not enter its denominator.",
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
    has_migrations = connection.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'grdb_migrations'"
    ).fetchone()[0]
    if not has_migrations:
        raise DataQualityError("schema mismatch: grdb_migrations is missing")
    migrations = [row[0] for row in connection.execute("SELECT identifier FROM grdb_migrations ORDER BY rowid")]
    if migrations != EXPECTED_MIGRATIONS:
        raise DataQualityError("schema mismatch: unexpected migration history")
    orphan_samples = connection.execute(
        "SELECT COUNT(*) FROM session_samples AS sample "
        "LEFT JOIN sessions AS session ON session.id = sample.sessionID WHERE session.id IS NULL"
    ).fetchone()[0]
    orphan_pids = connection.execute(
        "SELECT COUNT(*) FROM session_pids AS pid "
        "LEFT JOIN sessions AS session ON session.id = pid.sessionID WHERE session.id IS NULL"
    ).fetchone()[0]
    duplicate_sequence = connection.execute(
        "SELECT COUNT(*) FROM (SELECT sessionID, sequence, COUNT(*) AS count FROM session_samples "
        "GROUP BY sessionID, sequence HAVING count > 1)"
    ).fetchone()[0]
    return {
        "duplicateSequenceGroups": duplicate_sequence,
        "integrityCheck": "ok",
        "orphanPIDRows": orphan_pids,
        "orphanSampleRows": orphan_samples,
        "schemaCompatible": True,
    }


def _build_vehicle_report(
    connection: sqlite3.Connection,
    vehicle_id: str,
    session_ids: list[str],
    classification: str,
    vehicle_label: str,
) -> tuple[dict[str, Any], int]:
    """1つのvehicle/session scopeを匿名集計します。除外したdemo session数も返します。"""

    unique_ids = sorted(set(session_ids))
    placeholders = ",".join("?" for _ in unique_ids)
    session_sql = (
        "SELECT id, vehicleID, startedAt, endedAt, endReason, isDemo, adapterTransport, platform, "
        "appVersion, appBuild, pollingPolicyVersion, odometerStartKilometers, odometerEndKilometers, "
        "distanceSource, sampleCount, respondedCount, payloadByteCount, rawAvailability, archiveDigest "
        f"FROM sessions WHERE id IN ({placeholders}) AND deletedAt IS NULL ORDER BY startedAt, id"
    )
    stored = list(connection.execute(session_sql, unique_ids))
    if {row["id"] for row in stored} != set(unique_ids):
        raise DataQualityError("scope manifest references a missing or deleted session")
    if any(row["vehicleID"] != vehicle_id for row in stored):
        raise DataQualityError("scope manifest contains a session of another vehicle")
    for row in stored:
        _require_integer(row["startedAt"], "startedAt")
        if row["endedAt"] is not None:
            _require_integer(row["endedAt"], "endedAt")

    demo_rows = [row for row in stored if row["isDemo"]]
    if classification == "demo":
        if len(demo_rows) != len(stored):
            raise DataQualityError("demo classification contains a non-demo session")
        sessions, excluded = stored, 0
    else:
        sessions = [row for row in stored if not row["isDemo"]]
        excluded = len(demo_rows)

    kept_ids = [row["id"] for row in sessions]
    snapshots = _snapshots(connection, kept_ids)
    samples_by_session = _samples(connection, kept_ids)

    started = [_to_datetime(row["startedAt"]) for row in sessions]
    ended = [_to_datetime(row["endedAt"]) for row in sessions if row["endedAt"] is not None]
    session_durations = [(row["endedAt"] - row["startedAt"]) / 1000.0 for row in sessions if row["endedAt"] is not None]

    raw_durations: list[float] = []
    duration_differences: list[float] = []
    samples_per_session: list[int] = []
    raw_times: list[datetime] = []
    checks: Counter[str] = Counter()
    payload_total = 0
    sample_total = 0
    pid_samples: dict[tuple[int, int], list[tuple[sqlite3.Row, sqlite3.Row]]] = defaultdict(list)
    for session in sessions:
        rows = samples_by_session.get(session["id"], [])
        snapshot = snapshots.get(session["id"], {})
        samples_per_session.append(len(rows))
        sample_total += len(rows)
        payload_bytes = sum(len(row["payload"]) for row in rows)
        payload_total += payload_bytes
        responded = sum(1 for row in rows if row["outcome"] == 0)
        if [row["sequence"] for row in rows] != list(range(len(rows))):
            checks["sequenceGapSessions"] += 1
        if session["sampleCount"] != len(rows):
            checks["sampleCountMismatchSessions"] += 1
        if session["respondedCount"] != responded:
            checks["respondedCountMismatchSessions"] += 1
        if session["payloadByteCount"] != payload_bytes:
            checks["payloadByteCountMismatchSessions"] += 1
        if sorted(item["ordinal"] for item in snapshot.values()) != list(range(len(snapshot))):
            checks["pidOrdinalGapSessions"] += 1
        if session["rawAvailability"] == "cloudOnly" and rows:
            checks["cloudOnlyWithLocalSamplesSessions"] += 1
        if session["rawAvailability"] == "local" and session["sampleCount"] > 0 and not rows:
            checks["localWithoutSamplesSessions"] += 1
        elapsed_values = [row["elapsedMicroseconds"] for row in rows]
        tick_values = [row["tick"] for row in rows]
        if any(right < left for left, right in zip(elapsed_values, elapsed_values[1:])) or any(value < 0 for value in elapsed_values):
            checks["elapsedNotMonotonicSessions"] += 1
        if any(right < left for left, right in zip(tick_values, tick_values[1:])):
            checks["tickNotMonotonicSessions"] += 1
        for row in rows:
            if row["outcome"] not in OUTCOME_NAMES:
                raise DataQualityError("unknown sample outcome")
            has_payload = len(row["payload"]) > 0
            if (row["outcome"] == 0) != has_payload:
                checks["outcomePayloadMismatchRows"] += 1
            pid = snapshot.get((row["service"], row["pid"]))
            if pid is None:
                checks["samplesWithoutSnapshotRows"] += 1
            elif not (pid["support"] == "supported" and pid["isCollectionEnabled"]):
                checks["samplesForUnpolledPIDRows"] += 1
            pid_samples[(row["service"], row["pid"])].append((session, row))
        if rows:
            span = (max(elapsed_values) - min(elapsed_values)) / 1_000_000
            raw_durations.append(span)
            start = _to_datetime(session["startedAt"])
            raw_times.extend(start + timedelta(microseconds=value) for value in (min(elapsed_values), max(elapsed_values)))
            if session["endedAt"] is not None:
                duration_differences.append((session["endedAt"] - session["startedAt"]) / 1000.0 - span)
    for name in (
        "sequenceGapSessions", "sampleCountMismatchSessions", "respondedCountMismatchSessions",
        "payloadByteCountMismatchSessions", "pidOrdinalGapSessions", "cloudOnlyWithLocalSamplesSessions",
        "localWithoutSamplesSessions", "elapsedNotMonotonicSessions", "tickNotMonotonicSessions",
        "outcomePayloadMismatchRows", "samplesWithoutSnapshotRows", "samplesForUnpolledPIDRows",
    ):
        checks.setdefault(name, 0)

    day_set = {value.date() for value in started} | {value.date() for value in raw_times}
    distance_values = []
    distance_failed = 0
    for row in sessions:
        start = row["odometerStartKilometers"]
        end = row["odometerEndKilometers"]
        if start is None or end is None or not math.isfinite(start) or not math.isfinite(end) or start < 0 or end < start:
            distance_failed += 1
        else:
            distance_values.append(end - start)

    pid_reports = [
        _build_pid_report(key, entries, snapshots, len(sessions), len(day_set))
        for key, entries in sorted(pid_samples.items())
    ]
    observed_dates = sorted(day_set)

    report = {
        "adapterTransportDistribution": _counter(row["adapterTransport"] for row in sessions),
        "appVersionDistribution": _counter(f"{row['appVersion']}+{row['appBuild']}" for row in sessions),
        "classification": classification,
        "classificationDistribution": {classification: len(sessions)},
        "demoSessionCount": sum(1 for row in sessions if row["isDemo"]),
        "distanceSourceDistribution": _counter(row["distanceSource"] or "none" for row in sessions),
        "distance": {
            "establishedCount": len(distance_values),
            "failedCount": distance_failed,
            "totalKilometers": _rounded(sum(distance_values)),
        },
        "durationDifferenceSeconds": distribution(duration_differences),
        "endReasonDistribution": _counter(row["endReason"] or "recording" for row in sessions),
        "learningEligibility": {
            "status": "notEstablished",
            "reasons": ["operatingConditionCoverageNotEvaluated"]
            + ([] if classification == "realVehicle" else ["classificationNotRealVehicle"]),
        },
        "observationEndDate": observed_dates[-1].isoformat() if observed_dates else None,
        "observationStartDate": observed_dates[0].isoformat() if observed_dates else None,
        "pids": pid_reports,
        "platformDistribution": _counter(row["platform"] for row in sessions),
        "pollingPolicyVersionDistribution": _counter(str(row["pollingPolicyVersion"]) for row in sessions),
        "qualityChecks": dict(sorted(checks.items())),
        "rawAvailabilityDistribution": _counter(row["rawAvailability"] for row in sessions),
        "rawObservationDurationSeconds": {"distribution": distribution(raw_durations), "total": _rounded(sum(raw_durations))},
        "rawPayloadByteCount": payload_total,
        "recordedDayCount": len(day_set),
        "requestCount": sample_total,
        "samplesPerSession": distribution(samples_per_session),
        "sessionCount": len(sessions),
        "sessionDurationSeconds": {"distribution": distribution(session_durations), "total": _rounded(sum(session_durations))},
        "sessionEndDate": max(ended).date().isoformat() if ended else None,
        "sessionStartDate": min(started).date().isoformat() if started else None,
        "sessionStatusDistribution": _counter(_session_status(row) for row in sessions),
        "uploadedArchiveDistribution": _counter("present" if row["archiveDigest"] else "absent" for row in sessions),
        "vehicleLabel": vehicle_label,
    }
    return report, excluded


def _snapshots(connection: sqlite3.Connection, session_ids: list[str]) -> dict[str, dict[tuple[int, int], dict[str, Any]]]:
    """各sessionのPID snapshotをService/PID索引へ変換します。"""

    if not session_ids:
        return {}
    placeholders = ",".join("?" for _ in session_ids)
    rows = connection.execute(
        "SELECT sessionID, ordinal, service, pid, header, support, isCollectionEnabled, isFastGroup, "
        "definitionRevision, requiredByteCount, formula, minimumValue, maximumValue "
        f"FROM session_pids WHERE sessionID IN ({placeholders}) ORDER BY sessionID, ordinal",
        session_ids,
    )
    result: dict[str, dict[tuple[int, int], dict[str, Any]]] = defaultdict(dict)
    for row in rows:
        result[row["sessionID"]][(row["service"], row["pid"])] = {
            "ordinal": row["ordinal"],
            "header": row["header"],
            "support": row["support"],
            "isCollectionEnabled": bool(row["isCollectionEnabled"]),
            "isFastGroup": bool(row["isFastGroup"]),
            "definition": PIDDefinition(
                service=row["service"], pid=row["pid"], required_byte_count=row["requiredByteCount"],
                formula=row["formula"], minimum_value=row["minimumValue"], maximum_value=row["maximumValue"],
                revision=row["definitionRevision"],
            ),
        }
    return result


def _samples(connection: sqlite3.Connection, session_ids: list[str]) -> dict[str, list[sqlite3.Row]]:
    """対象sessionのRawサンプルをsequence順に読みます。"""

    if not session_ids:
        return {}
    placeholders = ",".join("?" for _ in session_ids)
    rows = connection.execute(
        "SELECT sessionID, sequence, tick, elapsedMicroseconds, service, pid, outcome, payload "
        f"FROM session_samples WHERE sessionID IN ({placeholders}) ORDER BY sessionID, sequence",
        session_ids,
    )
    result: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in rows:
        result[row["sessionID"]].append(row)
    return result


def _session_status(session: sqlite3.Row) -> str:
    """終了原因を表示状態へ変換します。"""

    if session["endReason"] is None:
        return "recording"
    return "completed" if session["endReason"] == "userStopped" else "interrupted"


def _build_pid_report(
    key: tuple[int, int],
    entries: list[tuple[sqlite3.Row, sqlite3.Row]],
    snapshots: dict[str, dict[tuple[int, int], dict[str, Any]]],
    session_count: int,
    recorded_day_count: int,
) -> dict[str, Any]:
    """1つのService/PIDを要求数・応答率・変換・周期へ集計します。"""

    outcome_counts = Counter({name: 0 for name in OUTCOME_NAMES.values()})
    decode_counts = Counter({name: 0 for name in DECODE_CLASSES})
    revisions: Counter[str] = Counter()
    support: Counter[str] = Counter()
    headers: Counter[str] = Counter()
    times_by_session: dict[str, list[tuple[int, int, int]]] = defaultdict(list)
    responded_sessions: set[str] = set()
    responded_days: set[date] = set()
    collection_sessions = 0
    fast_sessions = 0
    seen_sessions: set[str] = set()
    for session, row in entries:
        session_id = session["id"]
        snapshot = snapshots.get(session_id, {}).get(key)
        outcome_counts[OUTCOME_NAMES[row["outcome"]]] += 1
        if row["outcome"] == 0:
            decode_counts[classify(snapshot["definition"] if snapshot else None, bytes(row["payload"]))] += 1
            responded_sessions.add(session_id)
            responded_days.add((_to_datetime(session["startedAt"]) + timedelta(microseconds=row["elapsedMicroseconds"])).date())
        times_by_session[session_id].append((row["elapsedMicroseconds"], row["tick"], row["outcome"]))
        if snapshot and session_id not in seen_sessions:
            seen_sessions.add(session_id)
            revisions[str(snapshot["definition"].revision)] += 1
            support[snapshot["support"]] += 1
            headers["none" if snapshot["header"] is None else f"0x{snapshot['header']:X}"] += 1
            collection_sessions += snapshot["isCollectionEnabled"]
            fast_sessions += snapshot["isFastGroup"]
    request_intervals: list[float] = []
    response_intervals: list[float] = []
    tick_intervals: list[float] = []
    for rows in times_by_session.values():
        ordered = sorted(rows)
        request_intervals.extend((right[0] - left[0]) / 1_000_000 for left, right in zip(ordered, ordered[1:]))
        tick_intervals.extend(right[1] - left[1] for left, right in zip(ordered, ordered[1:]))
        answered = [item for item in ordered if item[2] == 0]
        response_intervals.extend((right[0] - left[0]) / 1_000_000 for left, right in zip(answered, answered[1:]))
    median_interval = percentile(response_intervals, 0.5)
    thresholds = {
        "over10Seconds": 10.0,
        "over30Seconds": 30.0,
        "over60Seconds": 60.0,
        "over3xMedian": 3.0 * median_interval if median_interval is not None else None,
        "over5xMedian": 5.0 * median_interval if median_interval is not None else None,
        "overMax10SecondsOr3xMedian": max(10.0, 3.0 * median_interval) if median_interval is not None else None,
    }
    requests = len(entries)
    return {
        "collectionEnabledSessionCount": collection_sessions,
        "decodeCounts": dict(decode_counts),
        "definitionRevisionDistribution": dict(sorted(revisions.items())),
        "fastGroupSessionCount": fast_sessions,
        "headerDistribution": dict(sorted(headers.items())),
        "longGapCounts": {
            name: sum(1 for value in response_intervals if threshold is not None and value > threshold)
            for name, threshold in thresholds.items()
        },
        "observedDayRate": _rounded(len(responded_days) / recorded_day_count) if recorded_day_count else None,
        "observedDayRateDenominator": recorded_day_count,
        "observedSessionRate": _rounded(len(responded_sessions) / session_count) if session_count else None,
        "observedSessionRateDenominator": session_count,
        "outcomeCounts": dict(outcome_counts),
        "pid": key[1],
        "requestCount": requests,
        "requestIntervalSeconds": distribution(request_intervals),
        "requestedSessionCount": len(times_by_session),
        "responseIntervalSeconds": distribution(response_intervals),
        "responseRate": _rounded(outcome_counts["responded"] / requests) if requests else None,
        "service": key[0],
        "supportDistribution": dict(sorted(support.items())),
        "tickInterval": distribution(tick_intervals),
    }


def _counter(values: Iterable[str]) -> dict[str, int]:
    """カテゴリ値を安定順の件数辞書へ変換します。"""

    return dict(sorted(Counter(values).items()))


def _require_integer(value: Any, name: str) -> None:
    """Unixエポックミリ秒の列がINTEGERで保存されていることを検証します。"""

    if isinstance(value, bool) or not isinstance(value, int):
        raise DataQualityError(f"{name} must be stored as integer epoch milliseconds")


def _to_datetime(milliseconds: int) -> datetime:
    """Unixエポックミリ秒をUTCのdatetimeへ変換します。"""

    _require_integer(milliseconds, "timestamp")
    return datetime(1970, 1, 1, tzinfo=timezone.utc) + timedelta(milliseconds=milliseconds)


def _required_string(mapping: dict[str, Any], key: str) -> str:
    """manifestの必須非空文字列を検証します。"""

    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise DataQualityError(f"manifest key {key} must be a non-empty string")
    return value


def _rounded(value: float | None) -> float | None:
    """匿名集計数値を再現可能な小数精度へ丸めます。"""

    return None if value is None else round(float(value), 6)
