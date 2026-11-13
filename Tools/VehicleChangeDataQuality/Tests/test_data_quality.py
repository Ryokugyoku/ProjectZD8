"""offline集計器のscope分離、匿名化、不変性、新スキーマ(insight-v1)の集計を検証します。"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from data_quality import DataQualityError, build_report, distribution, percentile
from privacy_validation import PrivacyValidationError, validate_report

VEHICLE_ID = "11111111-1111-4111-8111-111111111111"
SESSION_ID = "22222222-2222-4222-8222-222222222222"
DEMO_SESSION_ID = "33333333-3333-4333-8333-333333333333"
OTHER_VEHICLE_ID = "44444444-4444-4444-8444-444444444444"
OTHER_SESSION_ID = "55555555-5555-4555-8555-555555555555"
START_MS = int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp() * 1000)

SCHEMA = """
    CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
    CREATE TABLE sessions (
        id TEXT PRIMARY KEY, vehicleID TEXT NOT NULL, startedAt INTEGER NOT NULL, endedAt INTEGER,
        endReason TEXT, isDemo BOOLEAN NOT NULL, adapterName TEXT NOT NULL, adapterTransport TEXT NOT NULL,
        platform TEXT NOT NULL, deviceID TEXT NOT NULL, deviceName TEXT NOT NULL, appVersion TEXT NOT NULL,
        appBuild TEXT NOT NULL, pollingPolicyVersion INTEGER NOT NULL, odometerStartKilometers DOUBLE,
        odometerEndKilometers DOUBLE, distanceSource TEXT, sampleCount INTEGER NOT NULL,
        respondedCount INTEGER NOT NULL, payloadByteCount INTEGER NOT NULL, rawAvailability TEXT NOT NULL,
        archiveDigest TEXT, modifiedAt INTEGER NOT NULL, deletedAt INTEGER
    );
    CREATE TABLE session_pids (
        sessionID TEXT NOT NULL, ordinal INTEGER NOT NULL, service INTEGER NOT NULL, pid INTEGER NOT NULL,
        header INTEGER, support TEXT NOT NULL, isCollectionEnabled BOOLEAN NOT NULL, isFastGroup BOOLEAN NOT NULL,
        definitionRevision INTEGER NOT NULL, requiredByteCount INTEGER, formula TEXT, unit TEXT NOT NULL,
        minimumValue DOUBLE, maximumValue DOUBLE, PRIMARY KEY (sessionID, ordinal)
    );
    CREATE TABLE session_samples (
        sessionID TEXT NOT NULL, sequence INTEGER NOT NULL, tick INTEGER NOT NULL,
        elapsedMicroseconds INTEGER NOT NULL, service INTEGER NOT NULL, pid INTEGER NOT NULL,
        outcome INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY (sessionID, sequence)
    ) WITHOUT ROWID;
"""

# (sequence, tick, elapsed microseconds, outcome, payload)
SAMPLES = (
    (0, 0, 1_000_000, 0, b"\x01\x00"),
    (1, 1, 2_000_000, 0, b"\x01\x04"),
    (2, 2, 20_000_000, 0, b"\xff\xff"),
    (3, 3, 21_000_000, 2, b""),
    (4, 4, 22_000_000, 1, b""),
)


def manifest_for(*vehicles: dict) -> dict:
    """テスト用のscope manifestを返します。"""

    return {"inputKind": "physicalDeviceSnapshot", "vehicles": list(vehicles)}


def real_vehicle(session_ids: list[str] | None = None, vehicle_id: str = VEHICLE_ID, classification: str = "realVehicle") -> dict:
    """1台分のmanifest項目を返します。"""

    return {"vehicleID": vehicle_id, "classification": classification, "sessionIDs": session_ids or [SESSION_ID]}


class DataQualityTests(unittest.TestCase):
    """synthetic fixtureだけで匿名集計契約を検証します。"""

    def test_type7_percentiles_and_empty_distribution(self) -> None:
        """type 7 percentileの空、単数、偶数を固定します。"""

        self.assertIsNone(percentile([], 0.5))
        self.assertEqual(percentile([2], 0.9), 2)
        self.assertEqual(percentile([1, 3], 0.5), 2)
        self.assertEqual(distribution([])["count"], 0)

    def test_report_is_anonymous_deterministic_and_readonly(self) -> None:
        """同じfixtureから同じ匿名JSONを生成し入力を変更しません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest, output = root / "insight-v1.sqlite", root / "scope.json", root / "report.json"
            self._create_fixture(database)
            self._write_manifest(manifest, real_vehicle())
            before = self._digest(database)
            before_stat = (database.stat().st_size, database.stat().st_mtime_ns)
            first = build_report(database, manifest)
            second = build_report(database, manifest)
            self.assertEqual(first, second)
            self.assertEqual(before, self._digest(database))
            self.assertEqual(before_stat, (database.stat().st_size, database.stat().st_mtime_ns))
            self.assertEqual(first["contractVersion"], 2)
            self.assertEqual(first["calculationVersion"], 2)
            self.assertEqual(first["schemaContractVersion"], 2)
            self.assertEqual(first["sourceSchema"], "insight-v1")
            self.assertNotIn("scopes", first)
            vehicle = first["vehicles"][0]
            self.assertEqual(vehicle["vehicleLabel"], "V001")
            self.assertEqual(vehicle["requestCount"], 5)
            self.assertEqual(vehicle["rawPayloadByteCount"], 6)
            self.assertEqual(vehicle["sessionDurationSeconds"]["total"], 60.0)
            self.assertEqual(vehicle["sessionStatusDistribution"], {"completed": 1})
            self.assertEqual(vehicle["recordedDayCount"], 1)
            self.assertEqual(vehicle["sessionStartDate"], "2026-01-01")
            self.assertEqual(vehicle["adapterTransportDistribution"], {"bluetoothLowEnergy": 1})
            self.assertEqual(vehicle["distance"]["totalKilometers"], 1.0)
            self.assertTrue(all(value == 0 for value in vehicle["qualityChecks"].values()), vehicle["qualityChecks"])
            output.write_text(json.dumps(first, sort_keys=True), encoding="utf-8")
            validate_report(output, manifest)

    def test_pid_request_denominator_and_cadence_include_non_responses(self) -> None:
        """無応答行を分母に含む応答率、周期、定義改訂を集計します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            self._write_manifest(manifest, real_vehicle())
            pid = build_report(database, manifest)["vehicles"][0]["pids"][0]
            self.assertEqual((pid["service"], pid["pid"]), (1, 12))
            self.assertEqual(pid["requestCount"], 5)
            self.assertEqual(pid["outcomeCounts"], {"responded": 3, "noData": 1, "timedOut": 1, "failed": 0})
            self.assertEqual(pid["responseRate"], 0.6)
            self.assertEqual(pid["decodeCounts"]["numericFinite"], 3)
            self.assertEqual(pid["definitionRevisionDistribution"], {"2": 1})
            self.assertEqual(pid["supportDistribution"], {"supported": 1})
            self.assertEqual(pid["headerDistribution"], {"none": 1})
            self.assertEqual(pid["requestIntervalSeconds"]["count"], 4)
            self.assertEqual(pid["requestIntervalSeconds"]["max"], 18.0)
            self.assertEqual(pid["responseIntervalSeconds"]["count"], 2)
            self.assertEqual(pid["longGapCounts"]["over10Seconds"], 1)
            self.assertEqual(pid["tickInterval"]["median"], 1.0)
            self.assertEqual(pid["observedSessionRate"], 1.0)

    def test_decodes_with_each_sessions_own_snapshot(self) -> None:
        """同じPIDでも改訂が異なるsessionは各自のsnapshotで変換します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            second_id = "66666666-6666-4666-8666-666666666666"
            self._insert_session(database, second_id, VEHICLE_ID, is_demo=False, formula="A", revision=3, maximum=0.5)
            self._write_manifest(manifest, real_vehicle([SESSION_ID, second_id]))
            pid = build_report(database, manifest)["vehicles"][0]["pids"][0]
            self.assertEqual(pid["definitionRevisionDistribution"], {"2": 1, "3": 1})
            self.assertEqual(pid["decodeCounts"]["numericFinite"], 3)
            self.assertEqual(pid["decodeCounts"]["outOfDeclaredRange"], 3)

    def test_demo_sessions_are_excluded_unless_classified_demo(self) -> None:
        """demoフラグのsessionは明示分類がない限り集計から除外します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            self._insert_session(database, DEMO_SESSION_ID, VEHICLE_ID, is_demo=True)
            self._write_manifest(manifest, real_vehicle([SESSION_ID, DEMO_SESSION_ID]))
            report = build_report(database, manifest)
            self.assertEqual(report["vehicles"][0]["sessionCount"], 1)
            self.assertEqual(report["exclusions"]["demoSessionsWithoutDemoClassification"], 1)

            self._write_manifest(manifest, real_vehicle([DEMO_SESSION_ID], classification="demo"))
            demo = build_report(database, manifest)
            self.assertEqual(demo["vehicles"][0]["sessionCount"], 1)
            self.assertEqual(demo["vehicles"][0]["demoSessionCount"], 1)
            self.assertEqual(demo["classificationTotals"], {"demo": 1})
            self.assertIn("classificationNotRealVehicle", demo["vehicles"][0]["learningEligibility"]["reasons"])

            self._write_manifest(manifest, real_vehicle([SESSION_ID], classification="demo"))
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_summary_mismatch_is_reported(self) -> None:
        """sessions集計列とRaw行の不一致を品質検査へ出します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            connection = sqlite3.connect(database)
            connection.execute("UPDATE sessions SET sampleCount = 9, respondedCount = 9, payloadByteCount = 1")
            connection.execute("UPDATE session_samples SET elapsedMicroseconds = 0 WHERE sequence = 2")
            connection.commit()
            connection.close()
            self._write_manifest(manifest, real_vehicle())
            checks = build_report(database, manifest)["vehicles"][0]["qualityChecks"]
            self.assertEqual(checks["sampleCountMismatchSessions"], 1)
            self.assertEqual(checks["respondedCountMismatchSessions"], 1)
            self.assertEqual(checks["payloadByteCountMismatchSessions"], 1)
            self.assertEqual(checks["elapsedNotMonotonicSessions"], 1)

    def test_rejects_unknown_and_legacy_schema(self) -> None:
        """対象tableがないDBや旧スキーマをaccepted結果へ変換しません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "projectzd8.sqlite", root / "scope.json"
            sqlite3.connect(database).close()
            self._write_manifest(manifest, real_vehicle())
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)
            legacy = sqlite3.connect(database)
            legacy.execute("CREATE TABLE connection_sessions (id TEXT, accountIdentifier TEXT)")
            legacy.commit()
            legacy.close()
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_rejects_column_drift_and_text_timestamps(self) -> None:
        """列構成の差異とINTEGERでない時刻を拒否します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            self._write_manifest(manifest, real_vehicle())
            connection = sqlite3.connect(database)
            connection.execute("UPDATE sessions SET startedAt = '2026-01-01T00:00:00Z'")
            connection.commit()
            connection.close()
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)
            drift = root / "drift.sqlite"
            self._create_fixture(drift)
            connection = sqlite3.connect(drift)
            connection.execute("ALTER TABLE session_samples ADD COLUMN extra INTEGER")
            connection.commit()
            connection.close()
            with self.assertRaises(DataQualityError):
                build_report(drift, manifest)

    def test_rejects_scope_mismatch(self) -> None:
        """別車両のsessionや未知sessionを対象scopeへ混入させません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            self._insert_session(database, OTHER_SESSION_ID, OTHER_VEHICLE_ID, is_demo=False)
            self._write_manifest(manifest, real_vehicle([SESSION_ID, OTHER_SESSION_ID]))
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)
            self._write_manifest(manifest, real_vehicle(["77777777-7777-4777-8777-777777777777"]))
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_rejects_account_scoped_manifest(self) -> None:
        """アカウント階層を持つ旧形式のmanifestを受け付けません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, manifest = root / "insight-v1.sqlite", root / "scope.json"
            self._create_fixture(database)
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{"accountIdentifier": "a", "vehicles": [real_vehicle()]}],
            }), encoding="utf-8")
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_rejects_private_identifier_in_output(self) -> None:
        """manifest原識別子が匿名JSONへ混入した場合に拒否します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, report = root / "scope.json", root / "report.json"
            self._write_manifest(manifest, real_vehicle(["private-session-canary"], vehicle_id="private-vehicle-canary"))
            report.write_text(json.dumps({"unexpected": "private-vehicle-canary"}), encoding="utf-8")
            with self.assertRaises(PrivacyValidationError):
                validate_report(report, manifest)
            report.write_text(json.dumps({"note": "private-session-canary"}), encoding="utf-8")
            with self.assertRaises(PrivacyValidationError):
                validate_report(report, manifest)

    def test_rejects_forbidden_keys_and_identifier_shapes(self) -> None:
        """禁止key、UUID形式、長い16進列を拒否します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, report = root / "scope.json", root / "report.json"
            self._write_manifest(manifest, real_vehicle())
            for payload in (
                {"deviceName": "x"},
                {"nested": [{"adapterName": "x"}]},
                {"value": "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"},
                {"value": "0123456789abcdef0123456789abcdef"},
            ):
                report.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertRaises(PrivacyValidationError):
                    validate_report(report, manifest)

    def _write_manifest(self, path: Path, *vehicles: dict) -> None:
        """scope manifestを書き出します。"""

        path.write_text(json.dumps(manifest_for(*vehicles)), encoding="utf-8")

    def _create_fixture(self, database: Path) -> None:
        """製品schemaと同じ列順の最小synthetic DBを生成します。"""

        connection = sqlite3.connect(database)
        connection.executescript(SCHEMA)
        connection.execute("INSERT INTO grdb_migrations VALUES ('v1')")
        connection.commit()
        connection.close()
        self._insert_session(database, SESSION_ID, VEHICLE_ID, is_demo=False)

    def _insert_session(
        self,
        database: Path,
        session_id: str,
        vehicle_id: str,
        is_demo: bool,
        formula: str = "(A * 256 + B) / 4",
        revision: int = 2,
        maximum: float = 16383.75,
    ) -> None:
        """1sessionとそのPID snapshot、Raw行を追加します。"""

        connection = sqlite3.connect(database)
        responded = sum(1 for sample in SAMPLES if sample[3] == 0)
        payload_bytes = sum(len(sample[4]) for sample in SAMPLES)
        connection.execute(
            "INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (session_id, vehicle_id, START_MS, START_MS + 60_000, "userStopped", int(is_demo),
             "fixture-adapter-canary", "demo" if is_demo else "bluetoothLowEnergy", "iPhone",
             "fixture-device-id-canary", "fixture-device-name-canary", "1.0", "1", 1, 100.0, 101.0,
             "odometer", len(SAMPLES), responded, payload_bytes, "local", None, START_MS + 61_000, None),
        )
        connection.execute(
            "INSERT INTO session_pids VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (session_id, 0, 1, 12, None, "supported", 1, 1, revision, 2, formula, "rpm", 0.0, maximum),
        )
        for sequence, tick, elapsed, outcome, payload in SAMPLES:
            connection.execute(
                "INSERT INTO session_samples VALUES (?,?,?,?,?,?,?,?)",
                (session_id, sequence, tick, elapsed, 1, 12, outcome, payload),
            )
        connection.commit()
        connection.close()

    def _digest(self, path: Path) -> str:
        """fixture DBのSHA-256を返します。"""

        return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
