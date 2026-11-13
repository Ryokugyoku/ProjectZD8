# 車両固有変化検知 データ品質測定計画

## 1. 文書の責務と現在の結論

本書の責務は、実車ログ受領後に元データを変更せず、識別情報を成果物へ露出させず、工程3のデータ品質測定を再現可能に実行する入力、拒否条件、計算、匿名出力、判定基準を固定することである。

読む対象は初版データモデル(`insight-v1.sqlite`、スキーマ `v1`)だけである。旧データモデル(`projectzd8.sqlite`)は読まず、集計器も旧スキーマを拒否する。2026-07-28に旧スキーマの物理端末snapshotへ行った匿名測定と工程3判定は [`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md) が履歴として所有し、そのデータは新スキーマへ引き継がれない。**新スキーマの実車ログでの測定は未実施である。** 特徴量、走行状態の閾値、初期基準距離、スコア方式、モデル方式は引き続き決定しない。fixture は計算器の検証にだけ使い、実車のデータ量、PID readiness、走行状態 coverage、Production CloudKitの証拠にはしない。

独立したoffline集計器は `Tools/VehicleChangeDataQuality/` に置く(承認済み配置、§14)。製品のGRDB repositoryとデータベース初期化(`AppDatabase`)はマイグレーションを実行するため再利用しない。

## 2. 根拠と証拠境界

本計画は次を根拠とする。

- [`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md): 車両分離、verified numeric observation、immutable input manifest、実験判断の保留。
- [`VEHICLE_CHANGE_DETECTION_DATA_INVENTORY.md`](VEHICLE_CHANGE_DETECTION_DATA_INVENTORY.md): 現行SQLite schema、取得証跡、復元経路、実車ログ未取得。
- 現行 schema(`AppDatabaseMigrator` の `v1`): `sessions`、`session_pids`、`session_samples`(ほか車両・整備・同期の表。集計器は前3表だけを読む)。
- 現行 decode: 各セッションの `session_pids` 複写(式、必要byte数、単位、範囲、定義改訂)で `responded` 行を復号する。宣言min/maxの検査は集計器が `outOfDeclaredRange` として別に行う。
- 現行 状態: `sessions.rawAvailability`(`local` / `cloudOnly`)、`isDemo`、`endReason`(`userStopped` / `vehicleNoResponse` / `connectionLost` / `acquisitionFailed` / `appTerminated`)。

本書と将来の集計結果は、次を別証拠として扱う。

1. source/schema の静的確認
2. synthetic fixture test
3. offline snapshot の不変性
4. 物理端末からの抽出成功
5. 実車ログのデータ品質測定
6. Production CloudKit のアーカイブ現存・復元成功
7. TestFlight 版の動作

前段の成功を後段の成功として報告してはならない。

## 3. 入力契約

### 3.1 必須ファイルと同一 snapshot

入力 root は新規作成した非公開一時 directory とし、次を同一回の Application Support directory copy から受領する。

| ファイル | 必須性 | 規則 |
| --- | --- | --- |
| `insight-v1.sqlite` | 必須 | 原本ではなく offline snapshot だけを検査する |
| `insight-v1.sqlite-wal` | copy 元に存在した場合は必須 | main DB と同じ directory、同じ basename のまま保持する |
| `insight-v1.sqlite-shm` | copy 元に存在した場合は必須 | WAL と同じ copy operation で取得する |
| 非公開 scope manifest | 工程3の実車分類に必須 | 車両・session の原識別子を含むため成果物外、mode `0600` とする |
| 集計器version | 必須 | code内のschema contract、percentile method、long-gap候補、計算version(現行は各2)を匿名JSONへ出力する |

アプリは `DatabasePool` を使うため、WAL モードでの保存を想定する(実機での journal mode は未確認)。SQLite 本体だけを後から WAL/SHM と組み合わせない。WAL または SHM の片方だけがある、basename が異なる、copy 時点が異なる、copy 元での存在状態を記録していない場合は `incompleteSnapshot` として停止する。両方が存在しない場合も、自動的に「完全」と推測しない。アプリ終了後の単一 directory copy で copy 元にも両方が存在しなかったことを非公開抽出記録で確認できる場合にだけ続行する。この確認は運用手順の責務であり、集計器は検査しない。

### 3.2 非公開 scope manifest

`isDemo` は集計器が参照できるが、実車であることの確認は人間の責務である。集計器は車両名、VIN、adapter名、既知のfixture UUIDから分類を推測しない。非公開 scope manifest は次を持つ(アカウント階層は存在しない)。

```json
{
  "inputKind": "physicalDeviceSnapshot",
  "vehicles": [
    {"vehicleID": "<uuid>", "classification": "realVehicle", "sessionIDs": ["<uuid>"]}
  ]
}
```

- `inputKind`: `physicalDeviceSnapshot` または `syntheticFixture`(現行実装は `physicalDeviceSnapshot` のみ受理する)
- `vehicles[]`: 対象 `VehicleID`、分類、明示的な session ID の列
- 分類: `realVehicle`、`demo`、`fixture`、`indeterminate`
- 分類根拠種別(`userConfirmedRange`、`fixtureDeclaration`、`unconfirmed`)とsnapshot fingerprintへの非公開参照は、運用上の別記録として保持する。集計器は読まない。

scope manifest は入力選択にだけ使い、内容、hash 化した識別子、対応表を stdout、stderr、JSON、CSV、文書へ出さない。manifest と DB の不一致(存在しない・削除済み・別車両の session)は推測で補完せず全体停止する。

### 3.3 VehicleID の分離

アカウント識別子は存在しない。所有 key は常に `vehicleID` である。Raw は次の順で絞る。

1. 対象 `vehicleID` かつ `deletedAt IS NULL` の親 `sessions` を、manifest の session ID で選ぶ。
2. 取得した session が manifest の車両に属し、manifest の session ID と一致することを検証する。
3. `session_pids` / `session_samples` を親の `id` との join で読む。
4. 1 車両の集計を完了してメモリ上の識別子を破棄してから次へ進む。

出力には匿名車両ラベル `V001`(manifest 順)だけを記録する。同じ車両を複数 manifest 項目へ書いても統合しない。車両を跨いだ合計は、識別情報を混ぜない単純な総件数に限り、車両/PID品質の分母には使わない。

### 3.4 実車、DEMO、fixture、判定不能

分類は排他的に次の4種類とする。

| 分類 | 根拠 | 工程3品質集計 |
| --- | --- | --- |
| `realVehicle` | 対象車両と session 範囲をユーザーが識別子非表示で確認し、scope manifest に固定 | 対象候補(`isDemo = 1` の session は除外) |
| `demo` | 外部確認済みの DEMO session。`isDemo = 1` が必須 | demo として別集計(学習の分母に含めない) |
| `fixture` | 集計器 test が生成した synthetic DB | 除外し件数だけ報告 |
| `indeterminate` | DBだけでは確定できない、または manifest にない | 除外し件数だけ報告 |

`isDemo = 1` の session は、`demo` と明示分類した場合だけ集計し、それ以外では除外して `exclusions.demoSessionsWithoutDemoClassification` に件数だけを出す。`demo` と分類した車両に `isDemo = 0` の session が含まれる場合は全体停止する。`syntheticFixture` 入力から `realVehicle` 結果を生成してはならない。未分類 session を実車へ既定化してはならない。

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

集計器は Python standard library `sqlite3` の URI `file:<absolute-path>?mode=ro` を使い、明示的 read-only で開く。`immutable=1` は WAL を無視する危険があるため使わない。接続直後に `PRAGMA query_only = ON` と `PRAGMA trusted_schema = OFF` を接続ローカルに設定する。実行する SQL は、コード内に固定された `SELECT`、`PRAGMA integrity_check`、`PRAGMA table_info` だけである(SQL 文字列のallowlist照合機構は実装していない)。次は行わない。

- migration、DDL、DML、write transaction
- `VACUUM`、`REINDEX`、`ANALYZE`
- `PRAGMA journal_mode` の読取りを含む呼出しと変更
- checkpoint、attach、detach
- trigger/view の実行に依存する query
- 入力DBの copy、rename、repair、delete

値を条件へ渡す SQL はすべて `?` parameter binding を使う。table/column 名は外部入力から組み立てず、code 内の固定 allowlist からだけ選ぶ。

### 4.3 integrity と schema compatibility

preflight は集計より先に、次の順で行う。

1. main/WAL/SHM の file set と hash manifest を検証する(運用手順)。
2. read-only open が成功することを確認する。
3. `PRAGMA integrity_check` の全行が厳密に `ok` 1行だけであることを確認する。
4. `sessions`、`session_pids`、`session_samples` の列名と列順が versioned schema contract と完全一致することを確認する(`PRAGMA table_info`)。
5. `grdb_migrations` が存在し、履歴が `v1` だけであることを確認する。未知の将来 migration は互換性未確認として拒否し、集計器とcontract versionを更新するまで受理しない。
6. 親なしの `session_pids` / `session_samples`、同じ `(sessionID, sequence)` の重複を数える。
7. 時刻列が INTEGER(エポックms)で保存されていることを検査する。TEXT など他形式は拒否する。`schema_version` と `user_version` は互換性証拠にしない。

次は全体を拒否する: 空ファイル、0 table、対象 table 不在、未知列、必須列不足、列順不一致、破損、読み取り中の `SQLITE_CORRUPT` / `SQLITE_NOTADB` / `SQLITE_IOERR`、不完全WAL、`outcome` が `SampleOutcome` の値(0〜3)でない行、旧スキーマ(`connection_sessions` 等)、manifest と DB の不一致。

空DBや未知schemaでは、匿名の reason code だけを出して終了し、実車結果セクションを生成しない。

## 5. 列 allowlist と denylist

### 5.1 読取り allowlist

| table | 内部読取りを許可する列 | 使用目的 |
| --- | --- | --- |
| `sessions` | `id`、`vehicleID`、`startedAt`、`endedAt`、`endReason`、`isDemo`、`adapterTransport`、`platform`、`appVersion`、`appBuild`、`pollingPolicyVersion`、`odometerStartKilometers`、`odometerEndKilometers`、`distanceSource`、`sampleCount`、`respondedCount`、`payloadByteCount`、`rawAvailability`、`archiveDigest`、`deletedAt` | scope/join、時間、距離、取得条件cohort、集計列の整合、状態。識別値とdigestは内部だけ(`archiveDigest` は有無だけ出す) |
| `session_pids` | `sessionID`、`ordinal`、`service`、`pid`、`header`、`support`、`isCollectionEnabled`、`isFastGroup`、`definitionRevision`、`requiredByteCount`、`formula`、`minimumValue`、`maximumValue` | 取得時の復号規則と取得条件。`unit` は読まない |
| `session_samples` | `sessionID`、`sequence`、`tick`、`elapsedMicroseconds`、`service`、`pid`、`outcome`、`payload` | 親join、順序、周期、要求結果、decode。payloadはメモリ内だけ |

`id`、`vehicleID`、`sessionID`、`archiveDigest`、`payload`、`formula` は計算器内部専用であり出力 allowlist には含めない。payload は1行ずつdecodeし、集計counter更新後に保持しない。

### 5.2 禁止列 denylist

次の値は query の projection、debug representation、例外message、stdout、stderr、log、JSON、CSV、test failure diff、工程3文書へ出さない。

- VIN、`vehicles.obdIdentifier`、車両名
- `VehicleID`、session ID とそのhash
- `deviceID`、`deviceName`、`adapterName`
- `archiveDigest` の値
- Raw `payload`、payloadのhex/base64/文字列化、payload hash
- PID `formula` の文字列、個別走行の正確な時刻列、private scope manifest の内容

識別子を含む例外をそのまま再throw/printしない。外向け error は固定 reason code と件数だけに変換する。SQL trace callback、SQLite expanded SQL、Python object dump、shell `set -x` を禁止する。成果物検査(`privacy_validation`)は禁止key、UUID形式、長いhex、scope manifest の既知secret値が0件であることを機械確認し、さらにhuman reviewを行う。

## 6. 匿名化規則

現行の集計器は、manifest の車両順に `V001`、`V002` … を割り当てる(HMACや対応表は使わない)。ラベルは入力manifestの順序から決まるため、別snapshot間での追跡に使ってはならない。同じ入力から同じ結果を得るため、ラベルの並び、JSON key順、配列sort、浮動小数点丸めを versioned contract で固定する。匿名ラベルは個人を再識別するための永続pseudonymではない。

## 7. 集計単位と計算定義

### 7.1 セッション単位

対象は `deletedAt IS NULL`、`classification` と整合する `isDemo`、schema-valid の session とする。各sessionについて内部で次を計算し、個別session行は出力しない。

- session時間: `endedAt - startedAt`(エポックms)。未終了は不成立(`recording` として別計上)。
- Raw観測時間: Rawが1件以上なら `max(elapsedMicroseconds) - min(elapsedMicroseconds)`、0件なら不成立。
- sessionとRawの差: 両方成立時の `sessionDuration - rawObservationDuration`。負値も隠さず分布へ含める。
- sample数: 実Raw行数(無応答を含む)。`sampleCount`、`respondedCount`、`payloadByteCount` との差を一致/不一致の件数で持つ。
- 距離: start/endが有限、0以上、end >= start の場合だけ `end - start`。`distanceSource` の分布を併記する。
- 記録日: UTCで正規化した `startedAt` と、各Rawの時刻(`startedAt + elapsedMicroseconds`)のcalendar date。local timezone由来の意味は推測しない。

session別値は匿名車両単位で `count`、`min`、`p10`、`median`、`p90`、`p95`、`p99`、`max`、`IQR` へ縮約する。個別開始時刻、終了時刻、session IDは出さない。

### 7.2 車両単位

車両ラベルごとに次を計算する。

- session数、demo session数
- 観測開始日 = 最小UTC日、終了日 = 最大UTC日
- 記録日数 = distinct UTC日数。開始日と終了日の暦差+1ではない
- 合計走行距離、距離成立/不成立件数
- session時間合計と分布、Raw観測時間合計と分布、両者の差の分布
- 要求行合計(`requestCount`)とsession別sample数分布
- `adapterTransport`、`platform`、`appVersion+appBuild`、`pollingPolicyVersion`、`distanceSource`、`endReason`、`rawAvailability`、`archiveDigest` 有無の分布
- 分類、除外理由の分布

### 7.3 PID単位

車両ラベル、Service/PIDごとに次を計算する。

- 要求数(`requestCount`)と `outcome` 別件数(`responded` / `noData` / `timedOut` / `failed`)、応答率 = `responded` / 要求数。分母は `session_samples` の行数である。
- 要求したsession数、応答したsession率 = 応答が1件以上あるsession数 / 対象session数、応答した日率。
- 排他的decode結果件数(`responded` 行だけ。各行は自分のsessionの `session_pids` 複写で復号する)。
- 要求間隔、応答間隔、tick間隔の分布とlong gap候補別件数。
- 複写された定義改訂の分布、`support` の分布、CAN header の分布、収集有効・高頻度グループのsession数。

`noData` と `timedOut` は別々に数え、片方を他方の代わりにしない。応答率と観測session率を「故障」「劣化」の指標として読んではならない。

### 7.4 percentile

percentileは有限値だけを昇順sortし、Hyndman-Fan type 7で計算する。`n = 1` はその値、`n > 1` は `h = (n - 1) * p`、`j = floor(h)`、`g = h - j`、`x[j] + g * (x[j+1] - x[j])` とする。空集合は `null`。時間は内部で整数microsecond、距離は IEEE 754 double を使い、出力時だけ6桁へroundする。

### 7.5 取得周期とlong gap

取得間隔は、同じ session、Service/PID 内で `elapsedMicroseconds` の昇順に並べた隣接差である。

- 要求間隔: 隣接する要求行(結果を問わない)の差。
- 応答間隔: `responded` 行だけを並べた隣接差。long gap候補はこちらに適用する。
- tick間隔: 隣接する要求行の `tick` の差。

sessionを跨ぐ差は作らない。同じ時刻の0秒は有効観測として保持する。各PIDについて分布を出し、long gap のproduction閾値は決めず、次の**比較候補**ごとの件数を併記する。

- 10秒超、30秒超、60秒超の固定候補
- `3 * median` 超、`5 * median` 超の相対候補
- `max(10秒, 3 * median)` 超の複合候補

候補は観測分布を比較するためのものに限り、走行状態、異常、通知、学習可否の確定閾値ではない。応答間隔のgapは `timedOut` / `noData` の要求行を含む期間を含み得るため、`timedOut` と読み替えない。

## 8. 数値変換と学習適格性

### 8.1 排他的変換結果

各 `responded` 行は次の優先順で必ず1分類だけに入る(`noData` / `timedOut` / `failed` 行は復号対象外で `outcomeCounts` へ入る)。

1. `missingDefinition`: セッションの `session_pids` にそのService/PIDがない。
2. `unavailableFormula`: 複写はあるが `requiredByteCount` または `formula` がない。
3. `insufficientBytes`: payload byte数が必要数未満。
4. `invalidExpression`: 許可外構文、利用不能変数、ゼロ除算その他の式評価失敗。
5. `nonFinite`: 評価結果がNaNまたは±infinity。
6. `outOfDeclaredRange`: 有限だが、宣言min/maxのどちらかの範囲外。
7. `numericFinite`: 有限で、宣言範囲がないか宣言範囲内。

これらの合計は `responded` 行数と一致しなければならない。`outOfDeclaredRange` は有限評価の事実を失わないが、`numericFinite` と重複させない。

### 8.2 数値化成功と学習適格

`numericFinite` は計算上の変換成功であり、学習適格ではない。学習適格候補にはさらに次が必要である。

- `realVehicle` かつ `isDemo = 0`、vehicle一致、終了済みsession
- formula、required byte count、unit、validity constraintの根拠確認(コード同梱カタログの人間レビュー)
- 取得時点のdefinition revisionの固定(新スキーマでは `session_pids.definitionRevision` に記録される)
- 値域内、互換input manifest、除外理由なし
- 対象条件のデータ量とcoverageが工程3後に十分と判断されること

1つでも不足すれば `learningEligibility: notEstablished` とし、理由を列挙する(現行は `operatingConditionCoverageNotEvaluated`、実車分類でない場合は `classificationNotRealVehicle`)。数値化件数だけでPID readinessを宣言しない。

### 8.3 PID revision

新スキーマでは取得時のdefinition revisionがセッションごとに記録される。集計器は各 `responded` 行を自分のセッションの複写で復号し、PIDごとに `definitionRevisionDistribution` を出す。これは取得時の記録であり、再解析時の現行カタログの改訂ではない。

- セッション間で同じService/PIDのrevisionや式が異なる場合、cohortを混ぜない(特徴量設計で別cohortとして扱う)。
- 旧スキーマの実車ログには取得時revisionが無く、新スキーマへ移行しないため、`acquisitionRevisionUnavailable` の扱いは新データには適用しない。ただし、新データについても実取得での記録内容を確認するまでは設計上の期待にとどまる。

## 9. Raw利用可能性

sessionごとに `rawAvailability`(`local` / `cloudOnly`)と実Raw件数を使って分類する。

| 判定 | 条件 | 限界 |
| --- | --- | --- |
| `local` | `rawAvailability = local`、実Raw行 > 0(件数が `sampleCount` と整合) | このsnapshot内でのみ利用可能 |
| `cloudOnly` | `rawAvailability = cloudOnly`、実Raw行 = 0 | iCloud上のアーカイブの現存・復元成功は未証明。オフライン集計の対象外 |
| 不整合 | `local` なのに行がない、`cloudOnly` なのに行がある 等 | `qualityChecks` に件数を出す |

`archiveDigest` の有無だけを出し、digest値は出さない。Production CloudKitから実際にアーカイブを取得し、digest、`formatVersion`、`session_pids` / `session_samples` の整合、DB復元、decodeを検証するまでは「復元可能」と断定しない。本工程はCloudKitへ接続しない。

## 10. 匿名集計JSON出力契約

CSVはnested分布とreasonを安全に表現しにくいため、初版はcanonical JSONだけを採用する。UTF-8、LF、sorted keys、末尾改行あり、NaN/Infinity禁止、日時はUTC dateだけ、数値round規則固定とする。同じsnapshot、scope manifest、設定、集計器versionからbyte-for-byte同じJSONを生成する。

top-level contract(現行 version 2)は次のとおりである。

```json
{
  "contractVersion": 2,
  "calculationVersion": 2,
  "schemaContractVersion": 2,
  "sourceSchema": "insight-v1",
  "inputKind": "physicalDeviceSnapshot",
  "status": "accepted",
  "percentileMethod": "hyndmanFanType7",
  "evidenceBoundary": "anonymousOfflineAggregateOnly",
  "preflight": {},
  "vehicles": [],
  "classificationTotals": {},
  "exclusions": {},
  "warnings": []
}
```

各 `vehicles[]` は次を持つ。

- `vehicleLabel`、`classification`、`classificationDistribution`、`sessionCount`、`demoSessionCount`
- `sessionStartDate`、`sessionEndDate`、`observationStartDate`、`observationEndDate`、`recordedDayCount`
- `distance`(`totalKilometers`、`establishedCount`、`failedCount`)、`distanceSourceDistribution`
- `sessionDurationSeconds`、`rawObservationDurationSeconds`(各 `total` と `distribution`)、`durationDifferenceSeconds`
- `requestCount`、`rawPayloadByteCount`、`samplesPerSession`
- `pids[]`: `service`、`pid`、`requestCount`、`outcomeCounts`、`responseRate`、`decodeCounts`、`definitionRevisionDistribution`、`supportDistribution`、`headerDistribution`、`collectionEnabledSessionCount`、`fastGroupSessionCount`、`requestedSessionCount`、`observedSessionRate`(+分母)、`observedDayRate`(+分母)、`requestIntervalSeconds`、`responseIntervalSeconds`、`tickInterval`、`longGapCounts`
- `endReasonDistribution`、`sessionStatusDistribution`、`rawAvailabilityDistribution`、`uploadedArchiveDistribution`
- `adapterTransportDistribution`、`platformDistribution`、`appVersionDistribution`、`pollingPolicyVersionDistribution`
- `qualityChecks`: `sequenceGapSessions`、`sampleCountMismatchSessions`、`respondedCountMismatchSessions`、`payloadByteCountMismatchSessions`、`pidOrdinalGapSessions`、`cloudOnlyWithLocalSamplesSessions`、`localWithoutSamplesSessions`、`elapsedNotMonotonicSessions`、`tickNotMonotonicSessions`、`outcomePayloadMismatchRows`、`samplesWithoutSnapshotRows`、`samplesForUnpolledPIDRows`
- `learningEligibility`: 初版では不足理由を伴う `notEstablished`

分布objectは `count`、`min`、`p10`、`median`、`p90`、`p95`、`p99`、`max`、`iqr` を持つ。該当なしは0を捏造せず `null` とする。率は0...1で、分母も匿名件数として併記する。

`exclusions` は現行では `demoSessionsWithoutDemoClassification`(`isDemo = 1` で `demo` 分類でないため除外したsession数)だけを持つ。manifest不一致、スキーマ不一致、不完全snapshotは、部分的な `accepted` を出さず全体を停止する。個々の除外行は出力せず、件数だけを出す。VehicleID、session ID、VIN、端末名、payload、digest、個別走行時刻はJSONに存在してはならない。

## 11. 停止条件と工程3判定

### 11.1 実データ不足による停止

次のいずれかなら、特徴量、走行状態、閾値、スコア、モデル方式を決めずに停止する。

- 完全な offline snapshot、`integrity_check=ok`、互換schemaのいずれかがない。
- user-confirmed `realVehicle` の対象scopeがない。
- VehicleID/sessionの分離をmanifestとjoinで検証できない。
- 終了済み実車sessionが1件未満、またはlocal利用可能なRawが1行未満。
- 禁止情報が出力検査で1件でも検出された。
- fixture/DEMO/判定不能を実車から分離できない。
- session、日、距離、PID、周期、decode分類の要求集計に必要な分母が成立しない。
- 使用PIDのsession間でrevisionまたは式が異なり、cohortを分離できない。

「1件以上」は集計器を実行できる最低条件であって、特徴量やモデルを選ぶ十分量ではない。十分量の閾値は実データ分布を見ずに本書で決めない。

### 11.2 go / revise / no-go

| 判定 | 基準 |
| --- | --- |
| `go` | snapshot/integrity/schema/privacy/scopeが合格し、複数日・複数終了sessionの実車Rawから要求集計が成立し、少なくとも一部PIDでrevision互換性、有限範囲内変換、応答coverageを根拠付きで示せる。意味は「特徴量候補の比較へ進める」でありモデル採用ではない |
| `revise` | 原本を変更せず解消できるscope manifest、追加session/日/条件、Cloud復元確認の不足がある。必要追加証拠と再実行条件を列挙する |
| `no-go` | integrity/privacy/scope分離を保証できない、Rawが恒常的に利用不能、確認済み式・revisionが学習入力に成立しない、または原本変更・推測をしないと続行できない |

判定は車両別、必要ならPID別に行う。1車両のgoを別車両へ適用しない。goでも走行状態閾値、1,000 km候補値、スコア方式、statistical/ML model方式は確定しない。**新スキーマの実車ログがない現在の判定は `no-go`(測定不能)であり、`go` / `revise` の根拠となる実測はない。**

## 12. fixture検証契約

秘密情報を含まない一時synthetic fixtureをtestごとにOS一時directoryへ生成する。fixtureはrepositoryへcheck-inせず、test終了時の削除もtest自身が作成した一時directoryだけを対象とする。実データ一時領域は自動削除しない。

`Tools/VehicleChangeDataQuality/Tests/` は次を検証する(現行の15 test)。

1. type 7 percentileの単数、偶数、空集合。
2. 同じfixtureから同じ匿名JSONを生成し、DBのhash・size・mtimeが不変であること、`contractVersion` が2であること。
3. 無応答行(`noData` / `timedOut`)を分母に含む応答率、要求間隔、応答間隔、tick間隔、long gap件数。
4. 各セッションの `session_pids` 複写で復号し、同じPIDでも改訂の異なるsessionを混ぜないこと。
5. 7種類のdecode結果が排他的で、範囲外を `outOfDeclaredRange` へ分離すること。
6. `isDemo` セッションが `demo` 分類なしでは除外され、`demo` 分類でも非demoが混ざれば拒否されること。
7. `sessions` 集計列とRaw行の不一致、`elapsedMicroseconds` の非単調が `qualityChecks` へ出ること。
8. 空DB、旧スキーマ、列追加、INTEGERでない時刻、別車両のsession、存在しないsession、アカウント階層を持つ旧形式manifestが拒否されること。
9. 禁止key、manifest原識別子、UUID形式、長い16進列が匿名JSONに混入した場合に拒否されること。
10. 数値変換分類(`formula_evaluator`)の全区分。

次は集計器のtestでは検証しておらず、運用手順の責務である: main/WAL/SHMのSHA-256・file setの前後一致(実機snapshot)、不完全WAL、forbidden SQL tokenの拒否(機構自体が無い)。fixtureで確認できるのは計算契約、拒否動作、匿名出力、不変性だけである。実車の分布、データ量、PID readiness、走行状態coverage、Cloud復元、端末抽出は確認できない。

## 13. 方式比較

| 方式 | 配布対象との分離 | read-only保証 | 再現性/test | 判断 |
| --- | --- | --- | --- | --- |
| 製品Swift + GRDB | 低い。製品targetと既存repositoryに接近 | `AppDatabase` の初期化がマイグレーションを実行 | 既存型は再利用可能 | Production Swift禁止とmigration禁止に不適合 |
| XCTest内Swift | 製品target外 | SQLite/GRDB設定は可能 | fixture testは良いが通常の集計CLIにならない | 単独実行器の所有先にならない |
| standalone Swift CLI | 高い | SQLite C APIで可能 | build設定とtest targetが新規必要 | package/dependency/新directoryの負担が大きい |
| Python standard library | 高い | SQLite URI `mode=ro`、query_only、固定SELECT | tempfile、hash、JSON、unit testが標準libraryだけで可能 | 採用 |
| sqlite3 shell + SQL | 高い | `-readonly` | 単純集計は可能 | decode式、percentile、privacy/error contract、testが脆弱 |

外部dependencyを追加しない最小案は Python standard library である。製品target、アプリ、CloudKit、GRDB migrationへ依存しない。

## 14. 承認済み集計器配置

1. 単一責務: 互換なProjectZD8 SQLite offline snapshot(`insight-v1`)を読み取り専用で検証し、匿名データ品質JSONへ変換する。
2. 既存配置が所有しない理由: 製品のDomain/Application/Dataではなく、アプリから起動せず配布targetにも含めない保守・調査toolである。
3. path: `Tools/VehicleChangeDataQuality/`。test path: `Tools/VehicleChangeDataQuality/Tests/`。fixtureはOS一時directoryにtestごとに生成する。
4. 依存方向: Python standard libraryとoffline filesだけに依存し、`ProjectZD8/` source、Xcode target、CloudKit、端末APIへ依存しない。
5. 禁止依存: GRDB、MLX、製品composition、Application/Domain型のimport、network、CloudKit、app起動。
6. 代替案: `sqlite3 -readonly` の手動SQLは新directory不要だが、式評価、percentile、排他的分類、匿名化、再現性、不変性testを一体保証できないため採用しない。

実装はCLI orchestration(`vehicle_change_data_quality.py`)、schema/preflightと集計(`data_quality.py`)、decode分類(`formula_evaluator.py`)、privacy-safe JSON検査(`privacy_validation.py`、`validate_anonymous_output.py`)、fixture testへ責務分割し、generic `Helpers` / `Utils` を作らない。

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

人間はterminalへ内容を出さず、この非公開JSONから接続成功、bundle ID一致、インストール済みappを変更していないことを確認する。process実行中かどうかを `devicectl info apps` は証明しないため、アプリ終了はユーザー申告を抽出記録へ固定する。

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

実際のcopy結果でDBが `snapshot/ProjectZD8/insight-v1.sqlite` 配下になるか `snapshot/insight-v1.sqlite` になるかを、内容を表示せず確認する。次の `PROJECTZD8_DB_DIR` はmain DBを含むdirectoryの絶対pathへ設定する。

```zsh
read "PROJECTZD8_DB_DIR?Absolute directory containing insight-v1.sqlite: "
test -f "$PROJECTZD8_DB_DIR/insight-v1.sqlite"
find "$PROJECTZD8_DB_DIR" -maxdepth 1 -type f \
  \( -name 'insight-v1.sqlite' -o -name 'insight-v1.sqlite-wal' -o -name 'insight-v1.sqlite-shm' \) \
  -exec shasum -a 256 {} \; \
  > "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-sha256.txt"
find "$PROJECTZD8_DB_DIR" -maxdepth 1 -type f \
  \( -name 'insight-v1.sqlite' -o -name 'insight-v1.sqlite-wal' -o -name 'insight-v1.sqlite-shm' \) \
  -exec stat -f '%N %z %m' {} \; \
  > "$PROJECTZD8_CAPTURE_ROOT/private/snapshot-stat.txt"
ditto "$PROJECTZD8_DB_DIR" "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8"
chmod -R a-w "$PROJECTZD8_DB_DIR" "$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8"
```

hashは内容識別用だが個人識別子ではない。それでもprivate manifestだけに保存し、通常stdoutや工程3文書へ転記しない。報告する場合は「hash照合一致」と合計byteだけにする。

file set、hash、size、mtimeをbasenameだけで比較できるprivate fingerprintを作る。functionは入力を読取るだけである。

```zsh
projectzd8_fingerprint() {
  local projectzd8_fingerprint_dir="$1"
  (
    cd "$projectzd8_fingerprint_dir" || return 1
    for projectzd8_fingerprint_file in insight-v1.sqlite insight-v1.sqlite-wal insight-v1.sqlite-shm; do
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

preflightとして、`.schema` はterminalへ出さずprivate fileへ保存する。

```zsh
PROJECTZD8_WORK_DB="$PROJECTZD8_CAPTURE_ROOT/working/ProjectZD8/insight-v1.sqlite"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" 'PRAGMA integrity_check;' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema sessions' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-sessions.sql"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema session_pids' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-session-pids.sql"
sqlite3 -readonly "$PROJECTZD8_WORK_DB" '.schema session_samples' \
  > "$PROJECTZD8_CAPTURE_ROOT/private/schema-session-samples.sql"
test "$(wc -l < "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt" | tr -d ' ')" = 1
test "$(tr -d '\r\n' < "$PROJECTZD8_CAPTURE_ROOT/private/integrity.txt")" = ok
```

§14の集計器は次のcommandで実行する。

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

一時データ、private manifest、device情報、snapshot、working copy、匿名結果はユーザー承認なしに削除、移動、圧縮、Cloud保存しない。保持場所と容量だけを識別子なしで報告し、保持・削除の判断を待つ。この手順は新スキーマの実端末では未実行である(旧スキーマ向けの同手順を2026-07-28に実施した記録が監査文書にある)。

## 16. 工程3へ進むために不足している証拠

新スキーマの実車測定を行うために不足しているのは次である。

- 新データモデルで取得した実車ログ(複数日・複数の終了済みsession・距離・走行状態)
- 実取得で `session_pids` の複写、要求行(無応答の `outcome`)、`tick` / `elapsedMicroseconds`、集計列が設計どおり保存されることの確認
- `elapsedMicroseconds` の測定点の確定
- 確認済みPIDだけで定義した走行状態候補のcoverage
- 短session、欠測mask、cadence差に対する感度測定
- Production CloudKitアーカイブの現存とlocal解放後の復元E2E、および `cloudOnly` sessionの復元成功または利用不能の確定
- 匿名JSONに禁止情報がないことの機械検査とhuman review

これらが揃う前は工程3の測定結果、特徴量、走行状態閾値、1,000 km候補値、スコア方式、モデル方式を確定しない。
