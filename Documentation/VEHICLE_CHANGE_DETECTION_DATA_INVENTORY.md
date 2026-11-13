# 登録車両変化検知データインベントリ

> 更新: 本書は初版データモデル(`insight-v1`)の保存内容を記録する。旧データモデル(`projectzd8.sqlite`)に対する工程2の調査と、2026-07-28に旧スキーマで行った匿名実測は、[`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md)が履歴として所有する。旧データは新スキーマへ引き継がれず、本書の「実測できた量」には含めない。

## 1. 文書の責務と結論

この文書は、工程2「現在収集できているログの調査」として、登録車両専用の変化検知に再利用できる保存データ、読取境界、復元経路、データ不足を記録する。モデル学習、特徴量・スコア方式の決定、Production Swift、CloudKit schema、UIの変更は含まない。

結論は **工程3の実データ測定には no-go(新データモデルの実車ログがまだない)** である。コードとスキーマは、`VehicleID` ごとに、無応答を含む全要求と取得時のPID復号規則を持つRawを保存するよう設計されている。一方、この設計で取得された実車・実端末のデータは存在せず、本書の作成時点で新スキーマの実DBを読んでいない。データ量、取得周期、無応答率、変換成功率、走行状態coverageは測定できない。DEMOやtest fixtureは実車証拠に代用しない。

工程3へ進む条件は、新データモデルで実車を取得した端末の `insight-v1.sqlite` を読み取り専用で複製し、対象が実車であることをユーザーが確認することである(§12)。

## 2. 調査対象とデータ出所

### 2.1 読み取った証拠

| 種別 | 対象 | 確認した内容 | 証拠の限界 |
| --- | --- | --- | --- |
| 要件 | [`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md) | 車両分離、数値PID適格条件、Raw保持、macOS学習責務、実証分離 | 実データそのものではない |
| Domain | `DriveSession`、`SessionPID`、`SessionSample`、`SessionArchive`、`SampleOutcome`、`SessionEndReason`、`RawAvailability`、`DistanceSource`、`AcquisitionPollingPolicy` | 保存意味、要求結果、取得条件、アーカイブ単位 | 実際の取得量を証明しない |
| GRDB | `AppDatabaseMigrator`(唯一のスキーマ `v1`)、`AppDatabase` | SQLite列、制約、追記専用トリガー、保存場所 | 実インストール済みDBの状態を証明しない |
| 仕様 | `CLAUDE.md` | 同期・デモ・分析・削除の方針 | 実装の完了を意味しない |
| 旧実測 | [`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md) | 旧スキーマの8 session | 新スキーマへは引き継がれない |

VIN、`VehicleID`、session ID、端末名・端末ID、adapter名、アーカイブdigest、Raw payloadは本書へ出力していない。CloudKitへは読取を含めアクセスしていない。

### 2.2 端末内の保存場所と形式

- 製品DBは各アプリコンテナのユーザーApplication Support内、`ProjectZD8/insight-v1.sqlite` に置かれる(`AppDatabase.fileName`)。互換性のないスキーマへ変える場合はファイル名を変える規約である。旧 `projectzd8.sqlite` は読まない。
- macOSの通常パスは `~/Library/Application Support/ProjectZD8/insight-v1.sqlite`、iPhone/iPadでは `Ryokugyoku.ProjectZD8` のapp data container内の同じ相対パスである。
- 形式はGRDBで操作するSQLiteで、アプリ全体で1接続(`DatabasePool`)を共有する。外部キーは有効である。
- 時刻列(`…At`)はUTCのUnixエポックからのミリ秒(INTEGER)、ID列はUUIDの小文字文字列(TEXT)である。
- 写真本体は同じディレクトリ配下の `Photos/<id>.jpg` に置かれ、DBには持たない。

## 3. 現在のログ保存・復元フロー

```text
OBDアダプター
  -> Logging (接続 → 車両識別/登録 → セッション開始 → ポーリング → 保存 → 終了)
     -> sessions(1行) + session_pids(取得時のPID条件を複写、追記専用)
     -> session_samples(要求1件=1行、無応答も行、追記専用)

終了済みセッション
  -> SessionArchive(formatVersion付き、圧縮)を1回だけiCloud(CloudKitプライベートDB)へアップロード
     -> sessions.archiveDigest を記録
  -> 端末内Rawの解放: sessions.rawAvailability = cloudOnly(端末内の session_samples を解放)

cloudOnly セッションの分析要求
  -> iCloudからアーカイブを取得し、digest・formatVersionを検証
     -> session_pids / session_samples を復元(復元仕様の詳細と検証は未確認)
```

デモセッション(`isDemo`)と車両のPID収集設定(`vehicle_pid_settings`)は同期しない。CloudKit側のアーカイブが現存し、digest検証に成功するまで、`archiveDigest` があること自体は「復元可能」の証拠にならない。

## 4. 登録車両、セッション、取得元端末の関連付け

- セッションは常に `vehicleID` を持つ(`sessions.vehicleID NOT NULL`)。車両の識別・登録を経てから記録が始まる。アカウント識別子は存在しない。データの持ち主は端末のiCloudアカウントである。
- `session_pids` と `session_samples` は `sessionID` を持ち、車両は親の `sessions` を介して結合する。親が物理削除されると子もcascadeで削除される。
- 取得元として `platform`(`iPhone` / `iPad` / `mac`)、`deviceID`(インストール単位の識別値)、`deviceName`、`appVersion` / `appBuild` を保存する。`deviceID` と `deviceName` は匿名成果物へ出さず、cohort比較は匿名ラベルへ縮約して行う。
- 接続した経路として `adapterName` と `adapterTransport`(`bluetoothLowEnergy` / `bluetoothClassic` / `usbSerial` / `demo`)を保存する。`adapterName` は個体を示す文字列を含み得るため出力しない。

## 5. 保存されているフィールド一覧

### 5.1 `sessions`

| 分類 | 保存フィールド | 学習・監査上の意味 |
| --- | --- | --- |
| 所有 | `id`、`vehicleID` | セッション安定IDと登録車両。報告へ原値を出さない |
| 時間 | `startedAt`、`endedAt` | セッション開始・終了(エポックms)。`endedAt` と `endReason` は同時にNULL/非NULL(CHECK制約) |
| 終了区分 | `endReason` | `userStopped` / `vehicleNoResponse` / `connectionLost` / `acquisitionFailed` / `appTerminated` |
| デモ区分 | `isDemo` | 模擬アダプターで取得したデータか。集計から除外する根拠 |
| 取得環境 | `adapterName`、`adapterTransport`、`platform`、`deviceID`、`deviceName`、`appVersion`、`appBuild`、`pollingPolicyVersion` | 取得条件のcohort。名称・ID類は出力しない |
| 距離 | `odometerStartKilometers`、`odometerEndKilometers`、`distanceSource` | 有限・非減少なら差分距離を算出可能。採用元は `distanceSinceCodesCleared`(01/31)/`odometer`(01/A6)/`vehicleSpecificOdometer` |
| Raw概要 | `sampleCount`、`respondedCount`、`payloadByteCount` | 要求の総数(無応答を含む)、データ付き応答数、応答payload合計バイト数 |
| 保存・同期状態 | `rawAvailability`(`local` / `cloudOnly`)、`archiveDigest` | 端末内Rawの有無、アップロード済みアーカイブのSHA-256 |
| 管理 | `modifiedAt`、`deletedAt` | 同期用。`deletedAt` 付きの行は同期待ちの削除済み |

距離の優先順位は `DistanceSource.priority`(車種専用オドメーター > 標準オドメーター > 故障コード消去後距離)であり、採用元は `distanceSource` に保存される。

### 5.2 `session_pids`(取得時のPID条件、追記専用)

| フィールド | 内容 | 注意点 |
| --- | --- | --- |
| `sessionID`、`ordinal` | 親セッションとセッション内の順序(0始まり、欠番なし) | 主キー。`(sessionID, service, pid)` も一意 |
| `service`、`pid`、`header` | OBD要求識別子と、車種専用PIDの送信先CANヘッダー | 標準PIDの `header` はNULL |
| `support` | `supported` / `unsupported` / `unknown` | 取得開始時点の確認状態。「表にない」を `unsupported` と推測しない |
| `isCollectionEnabled`、`isFastGroup` | 収集有無、毎tick取得する高頻度グループか | 実際に要求するのは `support = supported` かつ収集有効のPID |
| `definitionRevision` | 複写元PID定義の改訂番号 | 取得時revisionの根拠 |
| `requiredByteCount`、`formula`、`unit`、`minimumValue`、`maximumValue` | 復号規則と値域 | 式未確認のPIDではNULL。分析はこの複写で復号する |

PID定義の原本は表ではなく、アプリ同梱のカタログ(`Domain/Catalog`、標準Service 01とZD8専用Service 21)である。カタログが後で改訂されても、既存セッションの復号は複写した規則で行う。

### 5.3 `session_samples`(Rawログ、追記専用)

| フィールド | 内容 | 注意点 |
| --- | --- | --- |
| `sessionID`、`sequence` | 親セッションとセッション内の通し番号(0始まり、欠番なし) | 主キー。記録順であり応答の到着順を保証しない |
| `tick` | この要求を発行したポーリングtickの番号 | 高頻度グループは毎tick、低頻度PIDは巡回して要求される |
| `elapsedMicroseconds` | セッション開始からの経過時間(単調増加時計) | 測定点(要求発行か応答受信か)は未確認。PID個別の応答遅延とは呼ばない |
| `service`、`pid` | OBD要求識別子 | |
| `outcome` | 0 responded / 1 noData / 2 timedOut / 3 failed | 無応答も行として残る。要求の分母は行数 |
| `payload` | サービス・PIDのエコーを除く応答データ | 無応答は空。通常集計・本書へ原値を出さない |

`sampleCount` と実Raw行数、`respondedCount` と `outcome = 0` の行数、`payloadByteCount` と payload 長合計の一致は、集計器が `qualityChecks` で検査する。

## 6. Rawログを数値PID時系列へ変換する処理

分析は、対象セッションの `session_pids` の複写で `session_samples` の `responded` 行を復号する。評価は制限付き式(A〜Hの応答バイト変数と四則演算、括弧、単項符号)で行い、Domainの `OBDPIDFormulaEvaluator` が本実装、offline集計器の `formula_evaluator.py` が同じ規則を意図した独立実装である(両者の出力が全入力で一致することは未検証)。

数値変換結果は、offline集計器では次の7種類へ排他的に分類する(値は行へ保存しない)。

| 区分 | 判定 |
| --- | --- |
| `numericFinite` | 複写があり、必要byte数と式があり、式評価が有限数値で成功し、宣言範囲内 |
| `outOfDeclaredRange` | 有限だが宣言された最小・最大の範囲外 |
| `missingDefinition` | そのService/PIDの複写がセッションにない |
| `unavailableFormula` | 複写はあるが必要byte数または式がない |
| `insufficientBytes` | payloadが必要byte数未満 |
| `invalidExpression` | 許可外構文、ゼロ除算など |
| `nonFinite` | 評価結果がNaNまたは±infinity |

「数値化成功」は要件上の「学習適格」と同義ではなく、範囲検証・定義の根拠確認・demo除外・実車確認を別に満たす必要がある。

## 7. 匿名化したデータ量の集計

### 7.1 この工程で実測できた量

| データ出所 | 登録車両 | セッション | 要求行 | 判定 |
| --- | ---: | ---: | ---: | --- |
| 新スキーマ(`insight-v1`)の実端末DB | 未取得 | 未取得 | 未取得 | 実データなし |
| Production CloudKit | 未取得 | 未取得 | 未取得 | 未アクセス |
| 旧スキーマの実車監査(2026-07-28) | 1 | 8 | 60,505(応答のみ) | 引き継がれない。[監査文書](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md)の履歴 |

新データモデルでの量は0ではなく「未測定」である。次の集計は算出できない。

- 車両別セッション数、観測期間、記録日数、合計走行距離、合計取得時間
- セッション別サンプル数分布、PID別要求数・応答率、数値化結果の件数
- PID別の取得周期分布、long gap、`timedOut` / `noData` / `failed` の比率
- 終了区分、デモ、`rawAvailability` の分布

### 7.2 実データ取得後の匿名集計規則

- `VehicleID` と session ID は選択条件にだけ使い、値もhashも出力しない。報告では安定ラベル `V001`、`V002` のみを使う(offline集計器は入力manifestの順にラベルを割り当てる)。
- VIN、車両名、`deviceID`、`deviceName`、`adapterName`、`archiveDigest`、Raw payloadはselect結果・ログ・CSV・報告書へ出さない。
- 端末は `platform` / `adapterTransport` / `appVersion+appBuild` のcohort集計だけに縮約する。`deviceID` による個体別集計が必要な場合は別承認とする。
- 日時は集計中に使用し、報告は必要最小限の観測期間と記録日数へ縮約する。個別走行の正確な時刻・経路は出さない。
- PIDはService/PIDと各セッションの `definitionRevision` で集計する。payloadはメモリ内でdecodeした直後に破棄し、失敗理由と件数だけを出す。

## 8. 学習へ利用できる情報

新データモデルで実車DBが取得でき、対象登録車両がユーザー確認できた場合、保存内容から次を作れる。

- `VehicleID` で分離したセッション集合と、`isDemo` による実車/デモの分離
- セッション境界、開始・終了、終了理由、取得platform・transport・app version
- PID別の要求数、`outcome` 別件数、応答率(要求の分母が行数から得られる)
- `elapsedMicroseconds` によるPID別時系列、要求間隔、tick間隔
- 取得時の式・単位・範囲・定義改訂で復号した数値PID値
- 有効な開始・終了累積距離があるセッションの記録距離と採用元
- Raw最初・最後の経過時間による実取得時間

これらは直ちに学習適格という意味ではない。値域検証、demo除外、実車確認、十分なcoverageを満たした行だけを工程3の候補にできる。

## 9. 現時点で利用できない情報とデータ品質上の懸念

| 不足または懸念 | 影響 |
| --- | --- |
| 新データモデルの実車ログがない | 全ての量・周期・無応答率・coverage判定が未実測 |
| PID個別の応答遅延、応答の到着順は保存されない | `elapsedMicroseconds` の測定点が未確認で、遅延やPID順序の影響を測れない可能性がある |
| `noData` と `failed` の内訳(ELM/STNのエラー、NRC)を保存しない | 車両非対応と通信失敗の詳細な分離ができない |
| adapterのfirmware、確立したOBDプロトコルを保存しない | adapter世代差を分離できない |
| polling巡回件数(`slowRequestsPerTick`)は版から導く | 値を変えて版を上げ忘れるとcohortを誤る |
| 車両の走行状態(ブレーキ等)を保存しない | 状態は取得済みPIDからの導出に限る |
| `sessions.endedAt - startedAt` は取得時間を過大評価し得る | Rawの `elapsedMicroseconds` の最小・最大を併記する |
| `archiveDigest` / `rawAvailability` はremote存在証明ではない | Production CloudKitのアーカイブ現存・復元成功を別検証する必要がある |
| `deviceID` はインストール単位で端末の個体差と一致しない | アプリの再インストールでIDが変わり得る(挙動は未確認) |

`vehicles.vin` と `vehicles.obdIdentifier` を含むDBは機微情報を含む。学習入力に不要であり、抽出時に列ごと除外する。

## 10. 工程3で測定すべき項目

工程3は対象実車を混在させず、セッション・時間単位の集計として次を測る(offline集計器が実装済みの項目を含む)。

1. 車両ラベル別のセッション数、観測開始日・終了日、記録日数、終了理由、取得platform・transport・app version。
2. `recordedDistanceKilometers` が成立する件数、成立しない理由、合計距離、`distanceSource` の分布。
3. `endedAt-startedAt` とRaw観測時間(`elapsedMicroseconds` の最大-最小)の両方、および差分。
4. セッション別要求行数のmin、p10、median、p90、p95、max、IQR。極端に短いセッションを明示する。
5. Service/PID別の要求数、`outcome` 別件数、応答率、応答したセッション率・記録日率。
6. 数値変換の排他的件数(§6の7区分)と、使われた `definitionRevision` の分布。
7. PID別の要求間隔・応答間隔・tick間隔(median、p90、p95、p99、max)と、`max(10秒, 3×median)` 等の候補を確定せず比較する長gap件数。
8. `sessions` 集計列とRaw行の整合、`elapsedMicroseconds` と `tick` の単調性、`session_pids` の欠番。
9. `rawAvailability` と `archiveDigest` の有無。実際の復元成功件数はProduction実機試験として別に測る。
10. 終了理由(`userStopped`、`vehicleNoResponse`、`connectionLost`、`acquisitionFailed`、`appTerminated`)の分布。
11. 実車/デモ判定: `isDemo` を一次根拠とし、ユーザー確認済みsession範囲を非公開manifestで固定する。推測で分類しない。
12. 確認済み車速・回転数・温度・負荷が存在する場合だけ、候補走行状態ごとの時間・session・日coverage。分類閾値はこの測定後に決める。
13. 1,000 km候補へ到達するまでの日数・セッション数・状態coverageの分布。単一車両の短期データだけで本番閾値を決めない。

## 11. 実車・Production環境で未確認の事項

- 対象実車の登録 `VehicleID` と、対象に含めてよいsession範囲
- 新スキーマで取得した実DBのrow count、integrity、WAL状態
- 実車での `outcome` の分布(`noData` / `timedOut` / `failed`)、PID別応答率、周期、gap、変換成功率、走行状態coverage
- `elapsedMicroseconds` の測定点と、要求発行から保存までの遅延
- Production CloudKitにセッションアーカイブが存在すること、アーカイブのダウンロード、digest検証、復元、decode完了
- 複数端末間・アプリversion間のデータ互換性
- 走行距離差分の実車妥当性
- 実端末でのRaw総容量、アーカイブ容量、転送所要時間

ローカルschema、unit test、Simulator、過去の実装記録は、これらのProduction/実車証拠を代替しない。

## 12. 次に必要な入力と読み取り専用抽出方法

### 12.1 必要なログの取得元

優先順位は次のとおりである。

1. 実車ログを取得したiPhone/iPad/Macの `Ryokugyoku.ProjectZD8` app data container(macOSでは `~/Library/Application Support/ProjectZD8/`)内の `insight-v1.sqlite`。
2. 端末でRawが解放済み(`cloudOnly`)の場合は、同じiCloudアカウントでProduction CloudKitから対象アーカイブを正規経路で復元した端末のapp data。復元操作はDBを変更するため、この工程の外でユーザーが明示実行する。

CloudKit Dashboardからの手作業export、デモDB、test fixtureを実車代替にはしない。

### 12.2 ユーザーに依頼する操作

1. 対象実車と、おおよその対象期間を画面上で確認する。VIN、`VehicleID` をチャットへ貼らない。
2. Rawが残る物理端末をMacへ接続し、ロック解除・信頼・Developer Mode等、Apple標準の読取条件を満たす。
3. 一貫したSQLite複製のためProjectZD8を終了する。ログの修復・削除・再収集はしない。
4. 作業担当へ「端末を接続しアプリを終了した」とだけ知らせる。端末名や識別子は不要である。
5. 端末にRawがない場合だけ、対象セッションをアプリの通常画面から復元するかを別途承認する。Production CloudKitへの書込みやschema変更は行わない。

### 12.3 読み取り専用の抽出

物理端末では `xcrun devicectl device copy from` を使い、app data container内の `Library/Application Support/ProjectZD8` ディレクトリを、新規のホスト側一時ディレクトリへコピーする。SQLite本体に加えて存在する場合は `insight-v1.sqlite-wal` と `insight-v1.sqlite-shm` も同時に取得するため、単一ファイルよりディレクトリcopyを優先する。具体的な手順は[`VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md`](VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md) §15を参照する。

複製後は原本を開かず、さらに作業用copyを作り、次だけを実行する。

```sh
sqlite3 -readonly /path/to/offline-copy/insight-v1.sqlite 'PRAGMA integrity_check;'
sqlite3 -readonly /path/to/offline-copy/insight-v1.sqlite '.schema sessions'
sqlite3 -readonly /path/to/offline-copy/insight-v1.sqlite '.schema session_pids'
sqlite3 -readonly /path/to/offline-copy/insight-v1.sqlite '.schema session_samples'
```

集計器はparameterized read queryだけを使用し、禁止列をstdoutへselectしない。CloudKit接続、GRDB migration、アプリ起動、write transaction、`VACUUM`、`REINDEX`、`PRAGMA journal_mode`変更は行わない。

### 12.4 必要なファイル、端末、容量

- 必須: `insight-v1.sqlite`。
- SQLiteが使用中だった可能性がある場合: 同じ時点の `insight-v1.sqlite-wal` と `insight-v1.sqlite-shm`。最も安全なのはアプリ終了後のProjectZD8 Application Supportディレクトリ一式。
- 必須端末: 実車ログを取得しRawを保持する端末、または復元済みの端末。
- 空き容量: コピー元Application Supportディレクトリの実サイズの2倍に、解析出力用1 GiBを加えた容量を確保する。`payloadByteCount` はpayload byteだけで、SQLite index、row、WAL、アーカイブのoverheadを含まないため容量見積りに単独使用しない。
- 容量確認値も合計byteだけを報告し、ファイル内容や識別子は表示しない。

### 12.5 工程3へ進むために不足している証拠

- 読取専用offline DB copyの `integrity_check=ok`
- スキーマ列と `grdb_migrations = v1` が本書の想定と一致すること
- 対象登録車両が実車であるというユーザー確認
- 対象車両に1件以上の終了済みsessionと1件以上のRaw行があること(`isDemo = 0`)
- Rawが端末にないsessionについてはProduction CloudKitからの復元成功、または利用不能という確定結果
- 匿名集計が禁止列・Raw payloadを出力しないことのreview

これらが揃えば工程3のデータ品質測定へ進める。揃う前に特徴量、走行状態閾値、1,000 km閾値、スコア方式、モデル方式を確定してはならない。
