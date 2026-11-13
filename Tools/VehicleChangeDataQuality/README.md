# Vehicle change data-quality tool

このdirectoryは、RevTorque Insight(ProjectZD8)の物理端末から取得したoffline SQLite snapshot(`Application Support/ProjectZD8/insight-v1.sqlite`)を、製品target・CloudKit・GRDB migrationから分離して匿名データ品質JSONへ変換する。Python標準ライブラリのみを使い、製品コードに依存しない。

## 入力

- 読み取り専用DB: 唯一のスキーマ `insight-v1`(`grdb_migrations` が `v1` のみ)。`sessions` / `session_pids` / `session_samples` の列を完全一致で検査し、旧スキーマ(`connection_sessions` など)は拒否する。
- 非公開scope manifest(アカウント階層なし。データは端末のiCloudアカウントに属するため):

```json
{
  "inputKind": "physicalDeviceSnapshot",
  "vehicles": [
    {"vehicleID": "<uuid>", "classification": "realVehicle", "sessionIDs": ["<uuid>"]}
  ]
}
```

`classification` は `realVehicle` / `demo` / `fixture` / `indeterminate`。`isDemo = 1` のsessionは `classification = demo` と明示した場合だけ集計し、それ以外では除外して件数を `exclusions` へ出す。`demo` 分類に非demo sessionが含まれる場合はエラーにする。

## 集計の要点

- 要求の分母は `session_samples` の行数(無応答を含む)。PIDごとに `outcome`(responded / noData / timedOut / failed)の件数と応答率を出す。
- 数値変換は各sessionの `session_pids` snapshot(式・必要バイト数・範囲・定義改訂)で行い、`definitionRevisionDistribution` に改訂を出す。
- 周期は `elapsedMicroseconds`(セッション開始からの単調増加時計)から求め、要求間隔・応答間隔・tick間隔を出す。
- `sessions` の集計列(件数・応答数・ペイロード合計)とRaw行の整合、経過時間とtickの単調性、PID snapshotの欠番などを `qualityChecks` へ出す。
- 時刻はINTEGERのUnixエポックミリ秒。TEXTなど他形式は拒否する。

出力契約は `contractVersion` / `calculationVersion` / `schemaContractVersion` = 2。出力は匿名ラベル(`V001`…)、件数、率、分布、品質検査だけを含み、VIN、VehicleID、session ID、端末ID・端末名、アダプター名、アーカイブdigest、Raw payloadは出力しない。生成後に `privacy_validation` が禁止key、UUID形式、長い16進列、manifest原値の混入を検査する。

```sh
python3 Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py \
  --database /path/to/working/ProjectZD8/insight-v1.sqlite \
  --scope-manifest /private/path/to/scope-manifest.json \
  --output /private/path/to/anonymous-data-quality.json

PYTHONPATH=Tools/VehicleChangeDataQuality \
  python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
```

fixture testはOS一時directory内だけでDBを生成し、実車データを使用しない。DBは `mode=ro` かつ `query_only` で開く。
