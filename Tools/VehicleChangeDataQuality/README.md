# Vehicle change data-quality tool

このdirectoryは、ProjectZD8の物理端末から取得したoffline SQLite snapshotを、製品target・CloudKit・GRDB migrationから分離して匿名データ品質JSONへ変換する。

入力は読み取り専用DBと非公開scope manifestであり、出力は匿名ラベル、件数、率、分布、品質検査だけを含む。VIN、Appleアカウント識別子、VehicleID、session ID、端末名、Raw payload、Manifest digestは出力しない。

```sh
python3 Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py \
  --database /path/to/working/ProjectZD8/projectzd8.sqlite \
  --scope-manifest /private/path/to/scope-manifest.json \
  --output /private/path/to/anonymous-data-quality.json

PYTHONPATH=Tools/VehicleChangeDataQuality \
  python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
```

fixture testはOS一時directory内だけでDBを生成し、実車データを使用しない。

