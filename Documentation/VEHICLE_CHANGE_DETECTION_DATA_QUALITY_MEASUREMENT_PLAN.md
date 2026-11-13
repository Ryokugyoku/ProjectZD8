# 車両固有変化検知 データ品質測定計画

## 1. 文書の責務と現在の結論

本書の責務は、実車ログ受領後に元データを変更せず、識別情報を成果物へ露出させず、工程3のデータ品質測定を再現可能に実行する入力、拒否条件、計算、匿名出力、判定基準を固定することである。

2026-07-28に物理端末snapshotを取得し、承認済み配置のoffline集計器で匿名測定を完了した。実測結果と工程3判定は [`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md) が所有する。特徴量、走行状態の閾値、初期基準距離、スコア方式、モデル方式は引き続き決定しない。fixture は計算器の検証にだけ使い、実車のデータ量、PID readiness、走行状態 coverage、Production CloudKitの証拠にはしない。

独立したoffline集計器は、ユーザーが本書§14の配置案を含む返答を示して作業続行を依頼した承認に基づき、`Tools/VehicleChangeDataQuality/`へ実装した。製品の `GRDBConnectionSessionRepository` と `GRDBOBDPIDDefinitionRepository` はinitializerでmigrationを実行するため再利用しない。

## 2. 根拠と証拠境界

本計画は次を根拠とする。

- [`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md): 車両・account 分離、verified numeric observation、immutable input manifest、実験判断の保留。
- [`VEHICLE_CHANGE_DETECTION_DATA_INVENTORY.md`](VEHICLE_CHANGE_DETECTION_DATA_INVENTORY.md): 現行 SQLite schema、Raw 復元、取得時 PID revision と DEMO flag の不足、実車ログ未取得。
- 現行 schema: `connection_sessions`、`connection_session_raw_logs`、`obd_pid_definitions`。
- 現行 decode: 定義の有無、式の有無、必要 byte 数、制限付き式評価、有限性までは確認するが、宣言 min/max は表示用 decode で検査しない。
- 現行 local/Cloud state: `empty`、`available`、`removed` と `notUploaded`、`pending`、`uploaded`、`failed`。

本書と将来の集計結果は、次を別証拠として扱う。

1. source/schema の静的確認
2. synthetic fixture test
3. offline snapshot の不変性
4. 物理端末からの抽出成功
5. 実車ログのデータ品質測定
6. Production CloudKit の Asset 現存・復元成功
7. TestFlight 版の動作

前段の成功を後段の成功として報告してはならない。

## 3. 入力契約

### 3.1 必須ファイルと同一 snapshot

入力 root は新規作成した非公開一時 directory とし、次を同一回の Application Support directory copy から受領する。

| ファイル | 必須性 | 規則 |
| --- | --- | --- |
| `projectzd8.sqlite` | 必須 | 原本ではなく offline snapshot だけを検査する |
| `projectzd8.sqlite-wal` | copy 元に存在した場合は必須 | main DB と同じ directory、同じ basename のまま保持する |
| `projectzd8.sqlite-shm` | copy 元に存在した場合は必須 | WAL と同じ copy operation で取得する |
| 非公開 scope manifest | 工程3の実車分類に必須 | account、車両、session の原識別子を含み得るため成果物外、mode `0600` とする |
| 集計器version | 必須 | 初版はcode内のschema contract、percentile method、long-gap候補、計算versionを固定して匿名JSONへ出力する |

SQLite 本体だけを後から WAL/SHM と組み合わせない。WAL または SHM の片方だけがある、basename が異なる、copy 時点が異なる、copy 元での存在状態を記録していない場合は `incompleteSnapshot` として停止する。両方が存在しない場合も、自動的に「完全」と推測しない。アプリ終了後の単一 directory copy で copy 元にも両方が存在しなかったことを非公開抽出記録で確認できる場合にだけ続行する。

### 3.2 非公開 scope manifest

DB schema には確実な DEMO flag がないため、集計器は車両名、VIN、表示識別値、endpoint、既知の fixture UUID から分類を推測しない。非公開 scope manifest は少なくとも次を持つ。

- `inputKind`: `physicalDeviceSnapshot` または `syntheticFixture`
- 1つ以上の account scope と、その内部選択値
- account scope 内の対象 `VehicleID`
- session ごとの `realVehicle`、`demo`、`fixture`、`indeterminate`
- 分類根拠種別: `userConfirmedRange`、`fixtureDeclaration`、`unconfirmed`
- snapshot fingerprintへの非公開参照
- 集計器のschema contract versionとcalculation version

scope manifest は入力選択にだけ使い、内容、hash 化した識別子、対応表を stdout、stderr、JSON、CSV、文書へ出さない。manifest の不一致行は推測で補完せず `scopeManifestMismatch` として除外または全体停止する。

### 3.3 account scope と VehicleID の分離

内部の所有 key は常に `(accountIdentifier, vehicleID)` の組である。`vehicleID` 単独の grouping、join、cache key、匿名ラベル再利用は禁止する。Raw は次の順で絞る。

1. parameterized predicate で1 account scope の親 `connection_sessions` を選ぶ。
2. 同じ predicate 内で対象 `vehicleID` を選ぶ。
3. 親の `id` と Raw の `sessionID` を join する。
4. scope manifest の session 分類を照合する。
5. 1 scope の集計を完了してメモリ上の識別子を破棄してから次 scope へ進む。

同じ `VehicleID` 文字列が複数 account に現れた場合も別車両として扱い、出力には匿名 scope `A001` と scope 内匿名車両 `V001` の組だけを記録する。account を跨いだ合計は、識別情報を混ぜない単純な総件数に限り、車両/PID品質の分母には使わない。

### 3.4 実車、DEMO、fixture、判定不能

分類は排他的に次の4種類とする。

| 分類 | 根拠 | 工程3品質集計 |
| --- | --- | --- |
| `realVehicle` | 対象車両と session 範囲をユーザーが識別子非表示で確認し、scope manifest に固定 | 対象候補 |
| `demo` | 外部確認済みの DEMO session | 除外し件数だけ報告 |
| `fixture` | 集計器 test が生成した synthetic DB | 除外し件数だけ報告 |
| `indeterminate` | DBだけでは確定できない、または manifest にない | 除外し件数だけ報告 |

`syntheticFixture` 入力から `realVehicle` 結果を生成してはならない。`physicalDeviceSnapshot` でも未分類 session を実車へ既定化してはならない。

## 4. offline copy の作成と読み取り専用検証

### 4.1 原本、snapshot、working copy

1. 端末の Application Support directory を空の `snapshot/` へ1回だけ copy する。
2. `snapshot/` を以後変更せず、main/WAL/SHM の SHA-256、byte size、mtime を非公開 manifest に記録する。
3. `snapshot/` 全体を空の `working/` へ copy する。SQLite単体を copy しない。
4. `snapshot/` と `working/` の file set、hash、size が一致することを確認する。
5. `snapshot/` と `working/` の権限から write bit を除く。集計プロセスも書込み不可の親 directory から実行する。
6. 検査前後に両方の hash、size、mtime、file set を比較する。

`sqlite3 .backup`、`VACUUM INTO`、checkpoint、DB修復は snapshot 作成手段に使わない。これらは見かけ上別DBを作れても、受領した main/WAL/SHM の不変な evidence copy ではない。

### 4.2 SQLite open contract

将来の集計器は Python standard library `sqlite3` の URI `file:<absolute-path>?mode=ro` を使い、明示的 read-only で開く。`immutable=1` は WAL を無視する危険があるため使わない。接続直後に `PRAGMA query_only = ON` と `PRAGMA trusted_schema = OFF` を接続ローカルに設定し、全 SQL 文を allowlist と照合する。

許可する操作は `SELECT`、`WITH ... SELECT`、`PRAGMA integrity_check`、`PRAGMA table_info`、`PRAGMA index_list`、`PRAGMA index_info`、`PRAGMA schema_version`、`PRAGMA user_version` に限る。次は禁止する。

- migration、DDL、DML、write transaction
- `VACUUM`、`REINDEX`、`ANALYZE`
- `PRAGMA journal_mode` の読取りを含む呼出しと変更
- checkpoint、attach、detach
- trigger/view の実行に依存する query
- 入力DBの copy、rename、repair、delete

値を条件へ渡す SQL はすべて `?` parameter binding を使う。table/column 名は外部入力から組み立てず、code 内の固定 allowlist からだけ選ぶ。

### 4.3 integrity と schema compatibility

preflight は集計より先に、次の順で行う。

1. main/WAL/SHM の file set と hash manifest を検証する。
2. read-only open が成功することを確認する。
3. `PRAGMA integrity_check` の全行が厳密に `ok` 1行だけであることを確認する。
4. `sqlite_schema` から対象3 table が実 table として存在することを確認する。
5. `PRAGMA table_info(?)` 相当は table 名を固定 allowlist から選び、列名、declared type、`notnull`、PK位置を versioned schema contract と完全照合する。
6. 親子 join、`sequence >= 0`、Service/PIDが0...255、時刻解釈、Raw payload型、session概要件数と実Raw件数の整合を read query で確認する。
7. `schema_version` と `user_version` は記録するが、それだけを互換性証拠にしない。現行 migration 名は SQLite の安定した互換version列ではないため、列契約を authority とする。

次は全体を拒否する: 空ファイル、0 table、対象 table 不在、未知列、必須列不足、型/PK不一致、破損、読み取り中の `SQLITE_CORRUPT` / `SQLITE_NOTADB` / `SQLITE_IOERR`、不完全WAL、同じ `(sessionID, sequence)` の重複、親なしRaw、scope manifest とDBのsnapshot hash不一致。

空DBや未知schemaでは、`status: rejected`、匿名の reason code、0件の診断だけを出し、実車結果セクションを生成しない。

## 5. 列 allowlist と denylist

### 5.1 読取り allowlist

| table | 内部読取りを許可する列 | 使用目的 |
| --- | --- | --- |
| `connection_sessions` | `id`、`accountIdentifier`、`startedAt`、`endedAt`、`endReason`、`stopReviewDecision`、`vehicleID`、`startingOdometerKilometers`、`endingOdometerKilometers`、`rawRecordCount`、`rawByteCount`、`localRawState`、`cloudSyncState`、`manifestDigest` | scope/join、時間、距離、状態、Manifest有無。識別値とdigestは内部だけ |
| `connection_session_raw_logs` | `sessionID`、`sequence`、`observedAt`、`batchElapsedNanoseconds`、`service`、`pid`、`payload` | 親join、順序、周期、decode。payloadはメモリ内だけ |
| `obd_pid_definitions` | `service`、`pid`、`vehicleModelCode`、`requiredByteCount`、`formula`、`unit`、`minimumValue`、`maximumValue`、`revision` | 現snapshotの変換候補と範囲、revision snapshot |

`id`、`accountIdentifier`、`vehicleID`、`sessionID`、`manifestDigest`、`payload`、`formula` は計算器内部専用であり出力 allowlist には含めない。payload は1行ずつdecodeし、集計counter更新後に保持しない。

### 5.2 禁止列 denylist

次の値は query の projection、debug representation、例外message、stdout、stderr、log、JSON、CSV、test failure diff、工程3文書へ出さない。

- VIN、`vehicleDisplayIdentifier`、`vehicleName`
- Apple account identifier とそのhash
- `VehicleID`、session ID とそのhash
- `acquisitionDeviceName`
- `macImportedDeviceID`、`macImportedDeviceName`
- Raw `payload`、payloadのhex/base64/文字列化、payload hash
- `manifestDigest` と `macImportedManifestDigest` の値
- PID `sourceURI`、個別走行の正確な時刻列、private scope manifest の内容

識別子を含む例外をそのまま再throw/printしない。外向け error は固定 reason code と件数だけに変換する。SQL trace callback、SQLite expanded SQL、Python object dump、shell `set -x` を禁止する。成果物検査は denylist の列名、UUID/長いhex/base64候補、scope manifest の既知secret値が0件であることを機械確認し、さらにhuman reviewを行う。

## 6. 匿名化規則

同じ offline snapshot と同じ設定から同じ結果を得るため、匿名化secretは設定で固定する。ただしsecretとHMAC値は成果物に保存しない。

1. account identifier を `HMAC-SHA-256(secret, "account\0" + value)` で内部sort keyへ変換し、昇順に `A001` から割り当てる。
2. 各account内で `HMAC-SHA-256(secret, "vehicle\0" + account + "\0" + vehicleID)` を内部sort keyへ変換し、`V001` から割り当てる。
3. HMACと原値の対応表はプロセスメモリだけに置き、出力前に破棄する。
4. 同一設定での再現性を保つため、labelの並び、JSON key順、配列sort、浮動小数点丸めをversioned contractで固定する。

匿名ラベルは個人を再識別するための永続pseudonymではない。別snapshot間の追跡が必要な場合もsecret再利用は別途承認対象とし、本書では許可しない。

## 7. 集計単位と計算定義

### 7.1 セッション単位

対象は `realVehicle`、account/vehicle一致、終了済み、schema-valid の session とする。各sessionについて内部で次を計算し、個別session行は出力しない。

- session時間: `endedAt - startedAt`。負値、非有限、未終了は不成立。
- Raw観測時間: Rawが2件以上なら `max(observedAt) - min(observedAt)`、1件なら0秒、0件なら不成立。
- sessionとRawの差: 両方成立時の `sessionDuration - rawObservationDuration`。負値も隠さず品質異常件数へ分類する。
- sample数: 実Raw行数。`rawRecordCount` との差も一致/不一致件数で持つ。
- 距離: start/endが有限、0以上、end >= start の場合だけ `end - start`。不成立理由は `missingStart`、`missingEnd`、`nonFinite`、`negative`、`decreasing` に排他的分類する。
- 記録日: UTCで正規化した `startedAt` のcalendar date。local timezone由来の意味は推測しない。

session別値は匿名車両単位で `count`、`min`、`p10`、`median`、`p90`、`p95`、`p99`、`max`、`IQR` へ縮約する。個別開始時刻、終了時刻、session IDは出さない。

### 7.2 車両単位

`(anonymousAccountLabel, anonymousVehicleLabel)` ごとに次を計算する。

- session数
- 観測開始日 = 対象sessionの最小UTC日、終了日 = 最大UTC日
- 記録日数 = distinct UTC日数。開始日と終了日の暦差+1ではない
- 合計走行距離 = 成立sessionの距離合計
- 距離成立/不成立件数と理由
- session時間合計と分布、Raw観測時間合計と分布、両者の差の分布
- Raw行合計とsession別sample数分布
- local/Cloud/Manifest状態、終了理由、review decision、分類、除外理由の分布

観測期間は要求されたUTC開始日と終了日を日単位で併記し、個別sessionの時刻は出さない。将来granularityを変更する場合は同じcontract versionの実行時判断にせず、出力contractを改訂する。

### 7.3 PID単位

account/車両、Service/PIDごとに次を計算する。

- 取得件数
- 観測session率 = そのPIDが1件以上ある対象session数 / Rawを1件以上持つ対象session数
- 観測日率 = そのPIDが1件以上あるUTC日数 / Rawを1件以上持つ対象UTC日数
- 排他的decode結果件数
- 連続取得間隔の分布とlong gap候補別件数
- 現snapshotのdefinition revision。取得時revisionではないことを明示する

要求したが応答しなかったPID、timeout、対応可否の分母が保存されていないため、「欠測率」「非応答率」は計算しない。観測session率・観測日率を欠測率へ読み替えてはならない。

### 7.4 percentile

percentileは有限値だけを昇順sortし、Hyndman-Fan type 7で計算する。`n = 1` はその値、`n > 1` は `h = (n - 1) * p`、`j = floor(h)`、`g = h - j`、`x[j] + g * (x[j+1] - x[j])` とする。空集合は `null`。時間は内部で整数nanosecond、距離は IEEE 754 double を使い、出力時だけ定めた桁数へroundする。

### 7.5 取得周期とlong gap

取得間隔は、同じ account、車両、session、Service/PID 内で `observedAt`、次に `sequence` の安定順へ並べた隣接差である。sessionを跨ぐ差、0未満、非有限は分布へ入れず品質異常へ数える。同じ時刻の0秒は有効観測として保持する。

各PIDについて `median`、`p90`、`p95`、`p99`、`max` を出す。long gap のproduction閾値は決めず、次の**比較候補**ごとの件数を併記する。

- 5秒超、10秒超、30秒超、60秒超の固定候補
- `3 * median` 超、`5 * median` 超の相対候補
- `max(10秒, 3 * median)` 超の複合候補

候補は観測分布を比較するためのものに限り、走行状態、異常、通知、学習可否の確定閾値ではない。`batchElapsedNanoseconds` はbatch全体の取得時間として別集計し、PID個別latencyとは呼ばない。

## 8. 数値変換と学習適格性

### 8.1 排他的変換結果

各Raw行は次の優先順で必ず1分類だけに入る。

1. `missingDefinition`: Service/PIDに定義がない。
2. `unavailableFormula`: 定義はあるが `requiredByteCount` または `formula` がない。
3. `insufficientBytes`: payload byte数が必要数未満。
4. `invalidExpression`: 許可外構文、利用不能変数、ゼロ除算その他の式評価失敗。
5. `nonFinite`: 評価結果がNaNまたは±infinity。
6. `outOfDeclaredRange`: 有限だが、両方存在する宣言min/maxの範囲外。
7. `numericFinite`: 有限で、宣言範囲がないか宣言範囲内。

これらの合計は対象Raw行数と一致しなければならない。`outOfDeclaredRange` は有限評価の事実を失わないが、`numericFinite` と重複させない。別補助値 `finiteEvaluationCount = numericFinite + outOfDeclaredRange` は出力してよい。

### 8.2 数値化成功と学習適格

`numericFinite` は計算上の変換成功であり、学習適格ではない。学習適格候補にはさらに次が必要である。

- `realVehicle`、account/vehicle一致、終了済みsession
- formula、required byte count、unit、validity constraintの根拠確認
- 取得時点のdefinition revisionまたは承認済み再decode revisionの固定
- 値域内、互換input manifest、除外理由なし
- 対象条件のデータ量とcoverageが工程3後に十分と判断されること

1つでも不足すれば `learningEligibility: notEstablished` とする。数値化件数だけでPID readinessを宣言しない。

### 8.3 PID revision

Raw/sessionには取得時definition revisionがない。したがって工程3は `obd_pid_definitions` を同じoffline snapshotから読み、各PIDの `analysisRevision` とschema/hashを固定するが、これを取得時revisionと呼ばない。

取得時revisionを外部証拠で固定できないPIDは次のように扱う。

- 数値変換品質の参考集計は `reanalyzedWithSnapshotRevision` と明示して実施できる。
- 学習適格は `notEstablished: acquisitionRevisionUnavailable` とする。
- revision間で式、byte数、単位、範囲が変わった可能性を否定できない場合、特徴量設計へ進めない。
- 将来のproduction変更やmigrationを本工程で行わない。

## 9. Raw利用可能性

sessionごとに、DB内の実Raw件数と保存状態を使って次へ排他的分類する。

| 判定 | 条件 | 限界 |
| --- | --- | --- |
| `localAvailable` | `localRawState == available`、実Raw > 0、概要件数と整合 | このsnapshot内でのみ利用可能 |
| `cloudRestoreCandidate` | local Rawなし、`localRawState == removed`、`cloudSyncState == uploaded`、Manifest非空 | CloudKit上の現存・復元成功は未証明 |
| `unavailable` | 上記以外、または状態/実件数不整合 | reason codeを併記 |

名称は `cloudRestorable` ではなく `cloudRestoreCandidate` とする。Production CloudKitから実際にAssetを取得しdigest、format、account、session、sequence、DB復元、decodeを検証するまでは「復元可能」と断定しない。本工程はCloudKitへ接続しない。

Manifestは有無だけを出し、digest値は出さない。local、Cloud、Manifest有無は個別分布と組合せ分布の両方を匿名件数で出す。

## 10. 匿名集計JSON出力契約

CSVはnested分布とreasonを安全に表現しにくいため、初版はcanonical JSONだけを採用する。UTF-8、LF、sorted keys、末尾改行あり、NaN/Infinity禁止、日時はUTC dateだけ、数値round規則固定とする。同じsnapshot、scope manifest、設定、集計器versionからbyte-for-byte同じJSONを生成する。

top-level contractは次のとおりである。

```json
{
  "contractVersion": 1,
  "inputKind": "physicalDeviceSnapshot",
  "status": "accepted",
  "schemaContractVersion": 1,
  "calculationVersion": 1,
  "percentileMethod": "hyndmanFanType7",
  "evidenceBoundary": "anonymousOfflineAggregateOnly",
  "scopes": [],
  "classificationTotals": {},
  "exclusions": {},
  "warnings": []
}
```

各 `scopes[].vehicles[]` は少なくとも次を持つ。

- `accountLabel`、`vehicleLabel`
- `sessionCount`
- `observationStartDate`、`observationEndDate`、`recordedDayCount`
- `distance.totalKilometers`、`distance.establishedCount`、`distance.failedCount`、`distance.failureReasons`
- `sessionDurationSeconds.total` と分布
- `rawObservationDurationSeconds.total` と分布
- `durationDifferenceSeconds` 分布と不整合件数
- `rawLogCount`
- `samplesPerSession` 分布
- `pids[]`: `service`、`pid`、`definitionRevision`、`revisionMeaning`、`observationCount`、`observedSessionRate`、`observedDayRate`、排他的decode件数、interval分布、long-gap候補別件数
- `endReasonDistribution`、`reviewDecisionDistribution`
- `localStateDistribution`、`cloudStateDistribution`、`manifestPresenceDistribution`、3者の組合せ分布
- `rawAvailabilityDistribution`
- `classificationDistribution`: 実車、DEMO、fixture、判定不能
- `excludedRowCount` と機械判定可能な `exclusionReasons`
- `learningEligibility`: 初版では不足理由を伴う `notEstablished`

分布objectは原則 `count`、`min`、`p10`、`median`、`p90`、`p95`、`p99`、`max`、`iqr` を持つ。該当なしは0を捏造せず `null` とする。率は0...1で、分母も匿名件数として併記する。

機械判定可能な除外 reason code は少なくとも次を固定する。

- `wrongAccountScope`
- `wrongVehicleScope`
- `unclassifiedSession`
- `demoSession`
- `fixtureSession`
- `activeSession`
- `missingVehicleAssociation`
- `missingRaw`
- `invalidTimestamp`
- `invalidDistance`
- `orphanRawRow`
- `duplicateSequence`
- `scopeManifestMismatch`
- `schemaIncompatible`
- `snapshotIncomplete`

個々の除外行は出力せず、reasonごとの件数だけを出す。VehicleID、session ID、account ID、VIN、端末名、payload、digest、個別走行時刻はJSONに存在してはならない。

## 11. 停止条件と工程3判定

### 11.1 実データ不足による停止

次のいずれかなら、特徴量、走行状態、閾値、スコア、モデル方式を決めずに停止する。

- 完全な offline snapshot、`integrity_check=ok`、互換schemaのいずれかがない。
- user-confirmed `realVehicle` の対象scopeがない。
- account/VehicleID/sessionの分離をmanifestとjoinで検証できない。
- 終了済み実車sessionが1件未満、またはlocal利用可能なRawが1行未満。
- PID定義を同じsnapshotから固定できない。
- 禁止情報が出力検査で1件でも検出された。
- fixture/DEMO/判定不能を実車から分離できない。
- session、日、距離、PID、周期、decode分類の要求集計に必要な分母が成立しない。
- revision不明の影響を分離できず、学習適格を判断できない。

「1件以上」は集計器を実行できる最低条件であって、特徴量やモデルを選ぶ十分量ではない。十分量の閾値は実データ分布を見ずに本書で決めない。

### 11.2 go / revise / no-go

| 判定 | 基準 |
| --- | --- |
| `go` | snapshot/integrity/schema/privacy/scopeが合格し、複数日・複数終了sessionの実車Rawから要求集計が成立し、少なくとも一部PIDでrevision互換性、有限範囲内変換、観測coverageを根拠付きで示せる。意味は「特徴量候補の比較へ進める」でありモデル採用ではない |
| `revise` | 原本を変更せず解消できるschema adapter、scope manifest、revision証拠、追加session/日/条件、Cloud復元確認の不足がある。必要追加証拠と再実行条件を列挙する |
| `no-go` | integrity/privacy/scope分離を保証できない、Rawが恒常的に利用不能、確認済み式・revisionが学習入力に成立しない、または原本変更・推測をしないと続行できない |

判定は車両別、必要ならPID別に行う。1車両のgoを別車両へ適用しない。goでも走行状態閾値、1,000 km候補値、スコア方式、statistical/ML model方式は確定しない。

## 12. fixture検証契約

集計器実装が承認された後、秘密情報を含まない一時synthetic fixtureをtestごとに生成する。fixtureはrepositoryへcheck-inせず、test終了時の削除もtest自身が作成した一時directoryだけを対象とする。実データ一時領域は自動削除しない。

最低限、次を検証する。

1. type 7 percentileの単数、偶数、奇数、空集合。
2. UTC distinct日数と観測開始/終了日。
3. session時間とRaw観測時間が異なるfixture。
4. session境界を跨がないPID別間隔と0秒間隔。
5. 全long-gap候補を同じ入力で比較し、候補を閾値決定と表現しないこと。
6. 7種類のdecode結果が排他的で合計Raw件数に一致すること。
7. finiteだが範囲外を `outOfDeclaredRange` へ分離すること。
8. 同じVehicleID文字列を別accountに置いても集計が混ざらないこと。
9. DEMO、fixture、判定不能が実車品質分母から除外され、件数だけ残ること。
10. JSONに禁止key、fixture内canary識別子、payload、UUID、長いhex/base64候補がないこと。
11. main/WAL/SHMのSHA-256、mtime、size、file setが実行前後で一致すること。
12. 空DB、対象table欠落、未知列、列型不一致、壊したDB、不完全WALが `rejected` となり、`status: accepted` や実車結果を生成しないこと。
13. 同じsnapshot/configを2回実行したJSONのSHA-256が一致すること。
14. forbidden SQL token、非parameterized value query、write attemptがtestで拒否されること。

fixtureで確認できるのは計算契約、拒否動作、匿名出力、不変性だけである。実車の分布、データ量、PID readiness、走行状態coverage、Cloud復元、端末抽出は確認できない。

## 13. 方式比較

| 方式 | 配布対象との分離 | read-only保証 | 再現性/test | 判断 |
| --- | --- | --- | --- | --- |
| 製品Swift + GRDB | 低い。製品targetと既存repositoryに接近 | 現repository initializerがmigrationを実行 | 既存型は再利用可能 | Production Swift禁止とmigration禁止に不適合 |
| XCTest内Swift | 製品target外 | SQLite/GRDB設定は可能 | fixture testは良いが通常の集計CLIにならない | 単独実行器の所有先にならない |
| standalone Swift CLI | 高い | SQLite C APIで可能 | build設定とtest targetが新規必要 | package/dependency/新directoryの負担が大きい |
| Python standard library | 高い | SQLite URI `mode=ro`、query_only、SQL allowlist | tempfile、hash、JSON、unit testが標準libraryだけで可能 | 承認後の最小案 |
| sqlite3 shell + SQL | 高い | `-readonly` | 単純集計は可能 | decode式、percentile、privacy/error contract、testが脆弱 |

外部dependencyを追加しない最小案は Python standard library である。製品target、アプリ、CloudKit、GRDB migrationへ依存しない。

## 14. 承認済み集計器配置

この配置は2026-07-28の工程3続行依頼により承認され、実装済みである。

1. 単一責務: 互換なProjectZD8 SQLite offline snapshotを読み取り専用で検証し、匿名データ品質JSONへ変換する。
2. 既存配置が所有しない理由: 製品のDomain/Application/Dataではなく、アプリから起動せず配布targetにも含めない保守・調査toolである。`PreviewSupport`はpreview fixture専用、`ProjectZD8Tests`は製品path mirror用である。
3. 提案path: `Tools/VehicleChangeDataQuality/`。
4. test path: `Tools/VehicleChangeDataQuality/Tests/`。fixtureはOS一時directoryにtestごとに生成する。
5. 依存方向: Python standard libraryとoffline filesだけに依存し、`ProjectZD8/` source、Xcode target、CloudKit、端末APIへ依存しない。
6. 禁止依存: GRDB、MLX、製品composition、Application/Domain型のimport、network、CloudKit、app起動。
7. 代替案: `sqlite3 -readonly` の手動SQLは新directory不要だが、式評価、percentile、排他的分類、匿名化、再現性、不変性testを一体保証できないため採用しない。

実装はCLI orchestration、schema/preflightと集計、decode分類、privacy-safe JSON検査、fixture testへ責務分割し、generic `Helpers` / `Utils` を作らない。

## 15. 実車ログ取得後の正確な実行手順

### 15.1 ユーザー操作と禁止事項

ユーザーが「端末を接続しアプリを終了した」と伝えた後にだけ開始する。TestFlight版を削除、更新、Debug版で上書きしない。アプリを再起動しない。物理端末上のDBを開かず、Production CloudKitへ接続しない。

端末selectorはチャットやshell historyへ貼らない。以下はzshで対話入力し、`set -x` は使わない。

```zsh
umask 077
read -s "PROJECTZD8_DEVICE_SELECTOR?Device selector (hidden): "
print
PROJECTZD8_CAPTURE_ROOT="$(mktemp -d /private/tmp/projectzd8-dq.XXXXXX)"
mkdir "$PROJECTZD8_CAPTURE_ROOT/device-info" "$PROJECTZD8_CAPTURE_ROOT/snapshot" "$PROJECTZD8_CAPTURE_ROOT/working" "$PROJECTZD8_CAPTURE_ROOT/private"
chmod 700 "$PROJECTZD8_CAPTURE_ROOT" "$PROJECTZD8_CAPTURE_ROOT/device-info" "$PROJECTZD8_CAPTURE_ROOT/snapshot" "$PROJECTZD8_CAPTURE_ROOT/working" "$PROJECTZD8_CAPTURE_ROOT/private"
```

端末接続状態と対象appの存在はJSON fileへ保存し、terminalへ識別子を表示しない。JSONは非公開入力で、匿名成果物ではない。

```zsh
xcrun devicectl device info details \
  --device "$PROJECTZD8_DEVICE_SELECTOR" \
  --quiet \
  --json-output "$PROJECTZD8_CAPTURE_ROOT/device-info/device.json"
xcrun devicectl device info apps \
  --device "$PROJECTZD8_DEVICE_SELECTOR" \
  --bundle-id Ryokugyoku.ProjectZD8 \
  --quiet \
  --json-output "$PROJECTZD8_CAPTURE_ROOT/device-info/app.json"
```

人間はterminalへ内容を出さず、この非公開JSONから接続成功、bundle ID一致、TestFlight版を変更していないことを確認する。process実行中かどうかを `devicectl info apps` は証明しないため、アプリ終了はユーザー申告を抽出記録へ固定する。

Application Support directoryを新規snapshotへ1回だけcopyする。`--remove-existing-content` は使わない。

```zsh
xcrun devicectl device copy from \
  --device "$PROJECTZD8_DEVICE_SELECTOR" \
  --domain-type appDataContainer \
  --domain-identifier Ryokugyoku.ProjectZD8 \
  --source 'Library/Application Support/ProjectZD8' \
  --destination "$PROJECTZD8_CAPTURE_ROOT/snapshot" \
  --quiet \
  --json-output "$PROJECTZD8_CAPTURE_ROOT/private/copy-result.json"
unset PROJECTZD8_DEVICE_SELECTOR
```

実際のcopy結果でDBが `snapshot/ProjectZD8/projectzd8.sqlite` 配下になるか `snapshot/projectzd8.sqlite` になるかを、内容を表示せず確認する。次の `PROJECTZD8_DB_DIR` はmain DBを含むdirectoryの絶対pathへ設定する。

```zsh
read "PROJECTZD8_DB_DIR?Absolute directory containing projectzd8.sqlite: "
test -f "$PROJECTZD8_DB_DIR/projectzd8.sqlite"
find "$PROJECTZD8_DB_DIR" -maxdepth 1 -type f \
  \( -name 'projectzd8.sqlite' -o -name 'projectzd8.sqlite-wal' -o -name 'projectzd8.sqlite-shm' \) \
  -exec shasum -a 256 {} \; \
  > "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-sha256.txt"
find "$PROJECTZD8_DB_DIR" -maxdepth 1 -type f \
  \( -name 'projectzd8.sqlite' -o -name 'projectzd8.sqlite-wal' -o -name 'projectzd8.sqlite-shm' \) \
  -exec stat -f '%N %z %m' {} \; \
  > "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-stat.txt"
ditto "$PROJECTZD8_DB_DIR" "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8"
chmod -R a-w "$PROJECTZD8_DB_DIR" "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8"
```

hashは内容識別用だが個人識別子ではない。それでもprivate manifestだけに保存し、通常stdoutや工程3文書へ転記しない。報告する場合は「hash照合一致」と合計byte数だけにする。

file set、hash、size、mtimeをbasenameだけで比較できるprivate fingerprintを作る。functionは入力を読取るだけである。

```zsh
projectzd8_fingerprint() {
  local projectzd8_fingerprint_dir="$1"
  (
    cd "$projectzd8_fingerprint_dir" || return 1
    for projectzd8_fingerprint_file in projectzd8.sqlite projectzd8.sqlite-wal projectzd8.sqlite-shm; do
      if test -f "$projectzd8_fingerprint_file"; then
        shasum -a 256 "$projectzd8_fingerprint_file"
        stat -f '%N %z %m' "$projectzd8_fingerprint_file"
      fi
    done
  )
}
projectzd8_fingerprint "$PROJECTZD8_DB_DIR" \
  > "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-fingerprint.txt"
projectzd8_fingerprint "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8" \
  > "$PROJECTZD8_CAPTURE_ROOT/private/working-before-fingerprint.txt"
cmp -s \
  "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-fingerprint.txt" \
  "$PROJECTZD8_CAPTURE_ROOT/private/working-before-fingerprint.txt"
```

集計器承認・実装前に可能なpreflightは次である。`.schema` はSQL defaultに機微値を含まない現行schemaだが、terminalへ出さずprivate fileへ保存する。

```zsh
PROJECTZD8_WORK_DB="$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8/projectzd8.sqlite"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" 'PRAGMA integrity_check;' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema connection_sessions' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-connection-sessions.sql"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema connection_session_raw_logs' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-raw-logs.sql"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema obd_pid_definitions' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-pid-definitions.sql"
test "$(wc -l < "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt" | tr -d ' ')" = 1
test "$(tr -d '\r\n' < "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt")" = ok
```

§14の実装済み集計器は次のcommandで実行する。

```zsh
python3 Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py \
  --database "$PROJECTZD8_WORK_DB" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json" \
  --output "$PROJECTZD8_CAPTURE_ROOT/anonymous-data-quality.json"
python3 Tools/VehicleChangeDataQuality/validate_anonymous_output.py \
  --report "$PROJECTZD8_CAPTURE_ROOT/anonymous-data-quality.json" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json"
projectzd8_fingerprint "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8" \
  > "$PROJECTZD8_CAPTURE_ROOT/private/working-after-fingerprint.txt"
cmp -s \
  "$PROJECTZD8_CAPTURE_ROOT/private/working-before-fingerprint.txt" \
  "$PROJECTZD8_CAPTURE_ROOT/private/working-after-fingerprint.txt"
```

実行後は入力不変性を再計算し、前後のhash、size、mtime、file setが一致しない場合は結果を破棄して停止する。同一入力・設定で2回生成し、JSON hash一致も確認する。工程3の結果文書へは検査済み匿名JSONの集計だけを転記する。

一時データ、private manifest、device情報、snapshot、working copy、匿名結果はユーザー承認なしに削除、移動、圧縮、Cloud保存しない。保持場所と容量だけを識別子なしで報告し、保持・削除の判断を待つ。

## 16. 工程3へ進むために不足している証拠

2026-07-28の実測後に不足しているのは次である。

- 追加日・距離・走行状態を含む縦断実車data
- 取得時PID definition revision、app version、schema version、polling policy snapshot
- 確認済みPIDだけで定義した走行状態候補のcoverage
- 短session、欠測mask、cadence差に対する感度測定
- Production CloudKit Assetの現存とlocal削除後の復元E2E
- local Raw不在sessionに対するProduction CloudKit復元成功または利用不能の確定
- 匿名JSONに禁止情報がないことの機械検査とhuman review

これらが揃う前は工程3の測定結果、特徴量、走行状態閾値、1,000 km候補値、スコア方式、モデル方式を確定しない。
