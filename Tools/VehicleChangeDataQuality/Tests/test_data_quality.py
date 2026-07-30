"""offline集計器のscope分離、匿名化、不変性を検証します。"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from data_quality import DataQualityError, build_report, distribution, percentile
from privacy_validation import PrivacyValidationError, validate_report


class DataQualityTests(unittest.TestCase):
    """synthetic fixtureだけで匿名集計契約を検証します。"""

    def test_type7_percentiles_and_empty_distribution(self) -> None:
        """type 7 percentileの空、単数、偶数を固定します。"""

        self.assertIsNone(percentile([], 0.5))
        self.assertEqual(percentile([2], 0.9), 2)
        self.assertEqual(percentile([1, 3], 0.5), 2)
        self.assertEqual(distribution([])["count"], 0)

    def test_grdb_naive_timestamp_is_interpreted_as_utc(self) -> None:
        """GRDBのtimezoneなしUTC保存形式を実日時として集計します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "projectzd8.sqlite"
            manifest = root / "scope.json"
            self._create_fixture(database, timestamp_suffix="")
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{"accountIdentifier": "fixture-account-canary", "vehicles": [{
                    "vehicleID": "11111111-1111-4111-8111-111111111111",
                    "classification": "realVehicle",
                    "sessionIDs": ["22222222-2222-4222-8222-222222222222"],
                }]}],
            }), encoding="utf-8")
            report = build_report(database, manifest)
            self.assertEqual(report["scopes"][0]["vehicles"][0]["sessionDurationSeconds"]["total"], 60.0)

    def test_report_is_anonymous_deterministic_and_readonly(self) -> None:
        """同じfixtureから同じ匿名JSONを生成し入力を変更しません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "projectzd8.sqlite"
            manifest = root / "scope.json"
            output = root / "report.json"
            self._create_fixture(database)
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{
                    "accountIdentifier": "fixture-account-canary",
                    "vehicles": [{
                        "vehicleID": "11111111-1111-4111-8111-111111111111",
                        "classification": "realVehicle",
                        "sessionIDs": ["22222222-2222-4222-8222-222222222222"],
                    }],
                }],
            }), encoding="utf-8")
            before = self._digest(database)
            before_stat = (database.stat().st_size, database.stat().st_mtime_ns)
            first = build_report(database, manifest)
            second = build_report(database, manifest)
            after = self._digest(database)
            after_stat = (database.stat().st_size, database.stat().st_mtime_ns)
            self.assertEqual(first, second)
            self.assertEqual(before, after)
            self.assertEqual(before_stat, after_stat)
            self.assertEqual(first["scopes"][0]["vehicles"][0]["rawLogCount"], 3)
            self.assertEqual(first["scopes"][0]["vehicles"][0]["rawPayloadByteCount"], 6)
            self.assertEqual(first["scopes"][0]["vehicles"][0]["sessionStatusDistribution"], {"completed": 1})
            self.assertEqual(first["scopes"][0]["vehicles"][0]["recordedDayCount"], 1)
            self.assertEqual(first["scopes"][0]["vehicles"][0]["qualityChecks"]["sequenceGapSessions"], 0)
            output.write_text(json.dumps(first, sort_keys=True), encoding="utf-8")
            validate_report(output, manifest)

    def test_rejects_unknown_schema(self) -> None:
        """対象tableがないDBをaccepted結果へ変換しません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "projectzd8.sqlite"
            sqlite3.connect(database).close()
            manifest = root / "scope.json"
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{"accountIdentifier": "a", "vehicles": [{
                    "vehicleID": "v", "classification": "realVehicle", "sessionIDs": ["s"],
                }]}],
            }), encoding="utf-8")
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_rejects_scope_mismatch(self) -> None:
        """別accountのsessionを対象scopeへ混入させません。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "projectzd8.sqlite"
            self._create_fixture(database)
            manifest = root / "scope.json"
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{"accountIdentifier": "wrong-account", "vehicles": [{
                    "vehicleID": "11111111-1111-4111-8111-111111111111",
                    "classification": "realVehicle",
                    "sessionIDs": ["22222222-2222-4222-8222-222222222222"],
                }]}],
            }), encoding="utf-8")
            with self.assertRaises(DataQualityError):
                build_report(database, manifest)

    def test_rejects_private_identifier_in_output(self) -> None:
        """manifest原識別子が匿名JSONへ混入した場合に拒否します。"""

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "scope.json"
            report = root / "report.json"
            manifest.write_text(json.dumps({
                "inputKind": "physicalDeviceSnapshot",
                "scopes": [{"accountIdentifier": "private-account-canary", "vehicles": []}],
            }), encoding="utf-8")
            report.write_text(json.dumps({"unexpected": "private-account-canary"}), encoding="utf-8")
            with self.assertRaises(PrivacyValidationError):
                validate_report(report, manifest)

    def _create_fixture(self, database: Path, timestamp_suffix: str = "+00:00") -> None:
        """製品schemaと同じ列順の最小synthetic DBを生成します。"""

        connection = sqlite3.connect(database)
        connection.executescript("""
            CREATE TABLE connection_sessions (
                id TEXT, accountIdentifier TEXT, startedAt TEXT, endedAt TEXT, endReason TEXT,
                stopReviewDecision TEXT, vehicleID TEXT, vehicleName TEXT, vehicleDisplayIdentifier TEXT,
                acquisitionPlatform TEXT, acquisitionDeviceName TEXT, startingOdometerKilometers REAL,
                endingOdometerKilometers REAL, distanceSourceModelCode TEXT, rawRecordCount INTEGER,
                rawByteCount INTEGER, localRawState TEXT, cloudSyncState TEXT, manifestDigest TEXT,
                macImportedDeviceID TEXT, macImportedDeviceName TEXT, macImportedAt TEXT,
                macImportedManifestDigest TEXT, rawLastAccessedAt TEXT
            );
            CREATE TABLE connection_session_raw_logs (
                sessionID TEXT, sequence INTEGER, observedAt TEXT, batchElapsedNanoseconds INTEGER,
                service INTEGER, pid INTEGER, payload BLOB
            );
            CREATE TABLE obd_pid_definitions (
                service INTEGER, pid INTEGER, header INTEGER, vehicleModelCode TEXT, nameKey TEXT,
                requiredByteCount INTEGER, formula TEXT, unit TEXT, minimumValue REAL, maximumValue REAL,
                sourceURI TEXT, revision INTEGER, summaryKey TEXT, highValueKey TEXT, lowValueKey TEXT,
                correlationKey TEXT
            );
        """)
        session_id = "22222222-2222-4222-8222-222222222222"
        connection.execute(
            "INSERT INTO connection_sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (session_id, "fixture-account-canary", f"2026-01-01T00:00:00{timestamp_suffix}", f"2026-01-01T00:01:00{timestamp_suffix}",
             "userDisconnected", None, "11111111-1111-4111-8111-111111111111", "fixture-name-canary", "fixture-vin-canary",
             "iPhone", "fixture-device-canary", 100.0, 101.0, None, 3, 6, "available", "uploaded", "digest-canary",
             None, None, None, None, None),
        )
        connection.execute(
            "INSERT INTO obd_pid_definitions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (1, 12, None, None, "fixture", 2, "(A * 256 + B) / 4", "rpm", 0.0, 16383.75,
             "fixture://source", 2, "s", "h", "l", "c"),
        )
        for sequence, second, payload in ((0, 1, b"\x01\x00"), (1, 2, b"\x01\x04"), (2, 20, b"\xff\xff")):
            connection.execute(
                "INSERT INTO connection_session_raw_logs VALUES (?,?,?,?,?,?,?)",
                (session_id, sequence, f"2026-01-01T00:00:{second:02d}{timestamp_suffix}", 1_000_000, 1, 12, payload),
            )
        connection.commit()
        connection.close()

    def _digest(self, path: Path) -> str:
        """fixture DBのSHA-256を返します。"""

        return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
