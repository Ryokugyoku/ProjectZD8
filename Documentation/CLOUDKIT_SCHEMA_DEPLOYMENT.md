# CloudKit スキーマの本番反映

TestFlight 版と App Store 版は CloudKit の**本番環境**を使う。本番環境では、レコード種別・フィールド・インデックスがアプリからの保存で自動作成されない。開発環境で動いていても、本番スキーマへ反映していない種別への保存は次のエラーで必ず失敗する。

```
"Invalid Arguments" (12/2006); server message = "Cannot create new type <種別> in production schema"
```

コンテナは `iCloud.Ryokugyoku.ProjectZD8`、データベースは private、ゾーンは既定ゾーン。

## いつ反映するか

次のどれかを含む変更を main へ入れたら、**TestFlight へ出す前に**本番スキーマへ反映する。

- レコード種別を足した。
- 既存の種別にフィールドを足した。
- クエリの条件や並び順に使うフィールドを足した(インデックスが要る)。

反映していない間は、その種別を使う機能が TestFlight 版で失敗する。削除済みの印(`AccountDeletionMarker`)が未反映だった時は、アカウント削除がクラウドのデータを消した後で止まり、ログアウトされなかった。

## コードが使うレコード種別

下の表はコード(`ProjectZD8/Data/Network/CloudKit/`)から書き起こしたもので、CloudKit Console の実際のスキーマと照合していない。種別・フィールドを変えたら同じ PR でこの表も更新する。

| レコード種別 | フィールド(型) | クエリ | 定義している型 |
| --- | --- | --- | --- |
| `ConnectionSessionRawLog` | `accountFingerprint`(String)、`sessionID`(String)、`manifestDigest`(String)、`payloadFormatVersion`(Int64)、`payloadAsset`(Asset) | `accountFingerprint ==` | `CloudKitConnectionSessionTransferRepository` |
| `ConnectionSessionMetadata` | `accountFingerprint`(String)、`sessionID`(String)、`manifestDigest`(String)、`payloadFormatVersion`(Int64)、`metadataData`(Bytes)、`endedAt`(Date/Time) | `accountFingerprint ==` | 同上 |
| `ConnectionSessionMacReceipt` | `accountFingerprint`(String)、`sessionID`(String)、`manifestDigest`(String)、`deviceID`(String)、`deviceName`(String)、`importedAt`(Date/Time) | `accountFingerprint ==` | 同上 |
| `ConnectionSessionDeletion` | `accountFingerprint`(String)、`sessionID`(String) | `accountFingerprint ==` | 同上 |
| `ConnectionSessionLocationTrack` | `accountFingerprint`(String)、`sessionID`(String)、`payloadFormatVersion`(Int64)、`manifestDigest`(String)、`sampleCount`(Int64)、`eventCount`(Int64)、`payloadAsset`(Asset) | `accountFingerprint ==` | `ConnectionSessionLocationTrackRecordMapper` |
| `VehicleCatalog` | `catalogAsset`(Asset)、`updatedAt`(Date/Time) | なし(レコードIDで取得) | `CloudKitVehicleRepository` |
| `MaintenanceCatalog` | `catalogAsset`(Asset)、`updatedAt`(Date/Time) | なし(レコードIDで取得) | `CloudKitMaintenanceRemoteStore` |
| `AccountDeletionMarker` | `deletedAt`(Date/Time) | なし(レコードIDで取得) | `CloudKitAccountDeletionMarkerStore` |

「クエリ」が `accountFingerprint ==` の種別は、`accountFingerprint` に Queryable インデックスが要る。インデックスは開発環境でも自動では作られないので、Console で足す。

## 反映の手順

1. 開発環境に種別を作る。Debug ビルドでその機能を1回動かせば、保存時に種別とフィールドが作られる。
2. [CloudKit Console](https://icloud.developer.apple.com/) でコンテナを開き、Development の Schema に種別・フィールド・必要なインデックスがあることを上の表と見比べる。
3. 「Deploy Schema Changes…」で差分を確かめ、本番へ反映する。
4. Production の Schema に種別があることを確かめる。
5. TestFlight 版でその機能を動かし、成功することを確かめる。

本番へ反映した種別とフィールドは削除できない。名前や型を変える時は、新しいフィールドを足す形にする。

## 反映漏れの確かめ方

TestFlight 版の macOS アプリを動かした Mac で、次のコマンドが本番スキーマに拒否された保存を返す。何も返らなければ、その時間内に拒否は起きていない。

```sh
/usr/bin/log show --last 1h --style compact --predicate 'process == "RevTorque Insight" AND subsystem == "com.apple.cloudkit" AND eventMessage CONTAINS "production schema"'
```

`log` は zsh の組み込みコマンドと名前が重なるので、`/usr/bin/log` と書く。

## スキーマ定義ファイル

リポジトリにスキーマ定義ファイル(`.ckdb`)は置いていない。Console の Schema 画面の「Export Schema」か、管理用トークンを保存した上での次のコマンドで書き出せる。

```sh
xcrun cktool export-schema --team-id Q6P6UR9XJG --container-id iCloud.Ryokugyoku.ProjectZD8 --environment production
```
