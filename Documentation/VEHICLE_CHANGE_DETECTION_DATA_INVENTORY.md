# 登録車両変化検知データインベントリ

> 更新: 本文は実車snapshot取得前の工程2時点を記録する。2026-07-28に物理端末から匿名実測を完了した後続証拠と現在の工程3判定は、[`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md)を参照する。

## 1. 文書の責務と結論

この文書は、工程2「現在収集できているログの調査」として、登録車両専用の変化検知に再利用できる現在の保存データ、読取境界、復元経路、データ不足を記録する。モデル学習、特徴量・スコア方式の決定、Production Swift、DB migration、CloudKit schema、UIの変更は含まない。

2026-07-28時点の結論は **工程3の実データ測定には条件付きno-go** である。コードとローカルスキーマには、登録 `VehicleID` ごとにRaw応答を抽出し、現在のPID定義で数値化する基礎がある。一方、この調査時に読み取れたMac製品DBと5件のSimulator DBはいずれもセッション0件で、接続済み物理端末もなく、Production CloudKitへはアクセスしていない。したがって、実車のデータ量、取得周期、欠測、変換成功率、走行状態coverageはまだ測定できない。DEMOやtest fixtureは実車証拠に代用していない。

工程3へ進む条件は、対象登録車両を含む製品DB一式を物理端末から読み取り専用で取得するか、同じアカウントでMacへ検証済みRawを復元した後にMac DBのオフライン複製を提供し、対象が実車であることをユーザーが確認することである。

## 2. 調査対象とデータ出所

### 2.1 読み取った証拠

| 種別 | 対象 | この工程で確認した内容 | 証拠の限界 |
| --- | --- | --- | --- |
| 要件 | [`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md) | 車両分離、数値PID適格条件、Raw保持、macOS学習責務、実証分離 | 実データそのものではない |
| 工程定義 | [`VEHICLE_CHANGE_DETECTION_CODEX_PROMPTS.md`](VEHICLE_CHANGE_DETECTION_CODEX_PROMPTS.md) | 実データ不在時の停止条件、匿名化、後続工程の入力 | 実データそのものではない |
| Domain / Application | `ConnectionSession`、Raw関連Entity/Repository、Logging、Analysis use case | 保存意味、車両結合、距離、復元、数値化、Mac向け読取能力 | 実際の取得量を証明しない |
| GRDB | migration、Record、Repository、PID seed | SQLite列、制約、保存場所、現在のPID定義 | インストール済み旧版DBや実機DBの状態を証明しない |
| CloudKit adapter | `CloudKitConnectionSessionTransferRepository` と同期use case | private databaseのrecord種別、JSON Asset、SHA-256検証、復元経路 | Production recordの存在・取得成功を証明しない |
| テスト | Logging、GRDB、Analysis、Raw復元、DEMO関連test | fixture上の関連付け・復元・数値化・分離動作 | 実車、実端末、Production CloudKitの証拠ではない |
| Mac製品DB | `~/Library/Application Support/ProjectZD8/projectzd8.sqlite` | `PRAGMA integrity_check=ok`、スキーマとPID定義、セッション件数 | セッション0件、Raw 0件 |
| Simulator DB | 検出した5件の製品DB | 各DBのセッション件数とRaw件数 | 全て0件。実車証拠に使用しない |
| 物理端末 | `devicectl` の接続可否だけを匿名確認 | この調査時に読取可能な接続済み端末がないこと | 端末DBは取得していない |

アカウント識別子、`VehicleID`、セッションID、VINまたは車両表示識別値、端末名、Manifest digest、Raw payloadはターミナル集計と本書へ出力していない。CloudKitへは読取を含めアクセスしていない。

### 2.2 端末内の保存場所と形式

- 製品DBは各アプリコンテナのユーザーApplication Support内、`ProjectZD8/projectzd8.sqlite` に置かれる。
- macOSの通常パスは `~/Library/Application Support/ProjectZD8/projectzd8.sqlite` である。iPhone/iPadでは `Ryokugyoku.ProjectZD8` のapp data container内の同じ相対パスになる。
- 形式はGRDBで操作するSQLiteである。接続概要は `connection_sessions`、未デコードRawは `connection_session_raw_logs`、現在のPID定義は `obd_pid_definitions` に保存される。
- Rawの親キーは `sessionID`、主キーは `(sessionID, sequence)`、親セッション削除時はcascade deleteされる。
- `connection_sessions` にはRaw件数とpayload byte数の概要が残るため、ローカルRaw削除後も一覧・転送状態を保持できる。

## 3. 現在のログ保存・復元フロー

```text
OBD取得adapter
  -> ReadMajorOBDPIDsUseCase
     -> 応答済みPIDだけをService/PID順にRaw observation化
        -> ConnectionSessionLifecycleModel
           -> GRDB connection_session_raw_logsへsequence付き追記

終了済みsession + local Raw
  -> ConnectionSessionTransferPackage v2 JSON
     -> CloudKit private database / ConnectionSessionRawLog / CKAsset
        -> SHA-256 manifest付き保存
  -> Raw非包含ConnectionSessionMetadataも別recordで保存

localRawState == removed の解析要求
  -> PrepareConnectionSessionRawLogUseCase
     -> sessionID + account scopeでAsset取得
     -> SHA-256、payload version、account、sessionIDを検証
     -> sequenceが0...n-1で連続することを検証
     -> 同一SQLite transactionでRaw子行を復元・読み戻し照合
     -> 既存の時系列decodeへ進む
```

CloudKit Raw Assetの現在形式は、決定的JSON（key sort、日時はmilliseconds since 1970）で、`sessionID`、`accountIdentifier`、`entries` を含むpayload format version 2である。各entryはRawテーブルと同じ6フィールドを持つ。セッションの車両、開始・終了、距離、取得端末、Raw概要は別の `ConnectionSessionMetadata` recordに符号化される。

`localRawState == removed` かつDB上で `cloudSyncState == uploaded`、非空のManifestを持つことは復元候補を示すが、CloudKit上のAssetが現存しDigest検証に成功するまでは「復元可能」と断定できない。`pending` / `failed` のままlocal Rawもない状態、Manifest不在、record削除、account不一致、version不一致、Digest不一致、sequence欠損は利用不能または復元失敗となる。

## 4. 登録車両、セッション、取得元端末の関連付け

- セッション開始時に安定した `ConnectionSessionID` とAppleアカウントscopeを保存する。
- 車両識別・登録が完了すると、同じ未終了セッションへ `ConnectionSessionVehicle` を結合する。これは登録 `VehicleID`、接続時点の車両名、接続時点の表示識別値のsnapshotである。
- Raw行は `sessionID` だけを持ち、`connection_sessions.vehicleID` とのjoinで登録車両へ属する。
- `ConnectionSessionRawLogRepository.entries(for:accountIdentifier:)` はアカウントと登録 `VehicleID` の両方で親セッションを絞り、セッション開始日時、セッションID、sequence順にRawを返す。コード上はMac学習入力に再利用できる既存境界である。
- 上記メソッド自体はGRDBのread transactionを使うが、製品Repositoryのinitializerはmigrationを実行し、通常のopen処理は保存先作成も行う。したがって、未確認DBを厳密な読み取り専用で監査する完成済みexport toolではない。オフライン複製には `sqlite3 -readonly` 等の別の読取専用手段が必要である。
- 取得元として `acquisitionPlatform`（iPhone / iPad / macOS）とユーザー向け端末名snapshotを保存する。安定した「取得元installation ID」は保存しない。`macImportedDeviceID` は取込先Macの受領証であり、取得元端末IDではない。
- 接続に使ったendpoint、adapter ID、transport、実通信/DEMOの区分はセッションへ保存しない。

## 5. 保存されているフィールド一覧

### 5.1 `connection_sessions`

| 分類 | 保存フィールド | 学習・監査上の意味 |
| --- | --- | --- |
| 所有 | `id`、`accountIdentifier` | セッション安定IDとaccount scope。報告へ原値を出さない |
| 時間 | `startedAt`、`endedAt` | 接続開始・終了。開始はRaw取得開始そのものとは限らない |
| 終了区分 | `endReason`、`stopReviewDecision` | 正常切断、中断、取得失敗、置換、sign-out、異常終了とユーザー確認 |
| 車両snapshot | `vehicleID`、`vehicleName`、`vehicleDisplayIdentifier` | 登録車両とのjoin。名称と表示識別値は学習に不要で報告から除外する |
| 取得端末snapshot | `acquisitionPlatform`、`acquisitionDeviceName` | platform別偏りを測れる。端末名は個人情報として出力しない |
| 距離 | `startingOdometerKilometers`、`endingOdometerKilometers`、`distanceSourceModelCode` | 有限・非減少なら差分距離を算出可能 |
| Raw概要 | `rawRecordCount`、`rawByteCount` | local削除後も件数とpayload byte数を保持 |
| local / Cloud状態 | `localRawState`、`cloudSyncState`、`manifestDigest`、`rawLastAccessedAt` | local利用可否、転送状態、復元整合性、cache access |
| Mac取込受領証 | `macImportedDeviceID`、`macImportedDeviceName`、`macImportedAt`、`macImportedManifestDigest` | 指定ManifestのMac取込実績。取得元端末とは別 |

距離の現在優先順位は、ZD8専用累積距離、Service 01 PID A6 odometer、Service 01 PID 31 distance since codes clearedの順である。ただしセッションには選択した `ConnectionSessionDistanceSource` 自体を保存せず、車種専用時のmodel codeだけを保存する。このため標準A6とPID 31のどちらが最終採用されたかをセッション列だけから一意に判定できない。

### 5.2 `connection_session_raw_logs`

| フィールド | 内容 | 注意点 |
| --- | --- | --- |
| `sessionID` | 親セッションID | 車両は親を介して結合する |
| `sequence` | セッション内0始まりの記録順 | Cloud復元時は欠番なしを要求する |
| `observedAt` | 応答群を受け取った実時間 | 1回のbatch内の全PIDで同一になる |
| `batchElapsedNanoseconds` | batch開始から全応答群受信までの単調時間 | PID個別response latencyではない |
| `service`、`pid` | OBD要求識別子 | headerはRawに保存されない |
| `payload` | Service/PIDを除く未デコードbyte列 | 本書・通常集計へ原値を出さない |

取得処理は「要求したPID一覧」ではなく「応答辞書に存在したPID」だけをRaw保存する。したがって非応答PID、timeoutした個別要求、試行回数、batch IDは残らず、真の欠測率の分母をRawだけから復元できない。同じ `observedAt` と `batchElapsedNanoseconds` によるbatch推定は可能だが、明示的なbatch IDではない。

### 5.3 `obd_pid_definitions`

Service、PID、任意のCAN header、任意の対象車両型式、名称key、必要byte数、制限付き変換式、単位、最小値、最大値、根拠URI、単調増加revision、説明用keyを保存する。現在確認したMac DBには169定義があり、内訳は次のとおりである。

| 区分 | 件数 | revision |
| --- | ---: | --- |
| 標準Service 01定義 | 167 | 2 |
| ZD8専用Service 21定義 | 2 | 1 |
| 必要byte数と式があり数値化候補 | 53 | 1または2 |
| metadataのみで式未確認 | 116 | 2 |

これは現在DBの**定義数**であり、実車が対応したPID数や取得件数ではない。Raw行とセッションには取得時点のPID definition revisionが保存されない。後日seedが更新されると、現在のdecodeは最新定義をRawへ適用するため、どのrevisionで当時の表示値を生成したかは再現できず、モデルinput manifestに必要なrevision固定も未実装である。

## 6. Rawログを数値PID時系列へ変換する現在の処理

`DecodeSessionLogTimelineUseCase` は解析開始時に現在の全PID定義を読み、Rawを128件ずつsequence cursorで取得して、Service/PID一致の定義式を `OBDPIDFormulaEvaluator` で評価する。出力はsequence、観測時刻、Service/PID、名称、数値、単位、車両型式、Raw payload、失敗理由を保持する。

現在の機械区分は次の3種類である。

| 区分 | 現在の判定 |
| --- | --- |
| 数値化可能 | 定義が存在し、必要byte数と式があり、式評価が有限数値で成功 |
| 変換式未確認 | 定義はあるが必要byte数または式がない（`unavailableFormula`） |
| 変換失敗 | 定義がない（`missingDefinition`）またはbyte不足・不正式・ゼロ除算等（`invalidPayload`） |

実データ集計では、要求された「変換式未確認」と「変換失敗」を、少なくとも `missingDefinition` と `invalidPayload` に分けて残すべきである。また、現在のevaluatorは有限値までは検証するが、定義の `minimumValue...maximumValue` 内かを検証しない。したがって「数値化成功」は要件上の「学習適格」と同義ではなく、範囲検証を工程3で別集計する必要がある。

## 7. 匿名化したデータ量の集計

### 7.1 この工程で実測できた量

| データ出所 | 登録車両 | セッション | Raw行 | 観測期間 | 記録日数 | 走行距離 | 取得時間 | 判定 |
| --- | ---: | ---: | ---: | --- | ---: | --- | --- | --- |
| 現在Mac製品DB | 0 | 0 | 0 | 該当なし | 0 | 該当なし | 該当なし | 実ログなし |
| Simulator DB 5件合計 | 0 | 0 | 0 | 該当なし | 0 | 該当なし | 該当なし | 実車証拠に不使用 |
| 物理iPhone/iPad | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 接続済み端末なし |
| Production CloudKit | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未アクセス |

セッションが0件のため、次の要求集計は算出不能である。

- 車両別セッション数、観測期間、記録日数、合計走行距離、合計取得時間
- セッション別サンプル数分布、PID別取得件数、数値化可能・式未確認・変換失敗件数
- PID別およびbatch別の取得周期分布、欠測、長い取得間隔
- 終了済み、接続中断、DEMO等のセッション区分
- local利用可能、iCloud復元可能、利用不能のRaw状態

ゼロ件という結果は「製品全体に実車ログが存在しない」ことを意味しない。このMacと検出済みSimulatorに集計対象がなく、この時点では物理端末やProduction CloudKitを読めなかったという限定された事実である。

### 7.2 実データ取得後の匿名集計規則

- account識別子は選択条件にだけ使い、値もhashも出力しない。
- `VehicleID` は調査ごとのランダムsaltを使ったHMAC-SHA-256で内部対応表を作り、報告では安定ラベル `V001`、`V002` のみを使う。saltと対応表は報告成果物に保存しない。
- セッションID、VIN、表示識別値、車両名、端末名、Manifest digest、Raw payloadはselect結果・ログ・CSV・報告書へ出さない。
- 端末は `iPhone` / `iPad` / `macOS` のplatform集計だけに縮約する。個体識別が必要な品質確認は、取得元installation IDが現在ないため実施不能と記録する。
- 日時は集計中に使用し、報告は必要最小限の観測期間と記録日数へ縮約する。個別走行の正確な時刻・経路は出さない。
- PIDはService/PIDとdefinition revisionで集計する。payloadはメモリ内でdecodeした直後に破棄し、失敗理由と件数だけを出す。

## 8. 学習へ利用できる情報

実車DBが取得でき、対象登録車両がユーザー確認できた場合、現在の保存内容から次を作れる。

- account scopeと安定 `VehicleID` で分離したセッション集合
- セッション境界、開始・終了、終了理由、取得platform
- Rawの記録順と観測時刻によるPID別時系列
- batch全体の取得時間、おおよそのbatch groupingとbatch間隔
- 現在の確認済み定義で有限数値化できるPID値、単位、現行revision
- Raw payload長と必要byte数の整合、変換失敗理由
- 有効な開始・終了累積距離があるセッションの記録距離
- Raw最初・最後の観測時刻による実取得時間
- 車速、回転数、温度、負荷等が実際に取得されている場合の後続coverage測定

これらは直ちに学習適格という意味ではない。revision固定、値域検証、DEMO除外、非応答分母、実車確認を満たした行だけを工程3の候補にできる。

## 9. 現時点で利用できない情報とデータ品質上の懸念

| 不足または懸念 | 影響 |
| --- | --- |
| 実車ログをこの工程で取得できていない | 全ての量・周期・欠測・coverage判定が未実測 |
| PID revisionをRaw/セッションへ固定していない | 取得時定義の再現、immutable input manifest、revision互換性判定ができない |
| DEMOフラグと接続endpointを保存していない | synthetic VIN等の現行実装知識に依存しない確実なDEMO除外ができない |
| 要求一覧、非応答、timeout、batch IDを保存していない | 真の欠測率、試行成功率、車両非対応と通信欠損の分離ができない |
| latencyがbatch単位 | PID個別応答時間やPID順序による遅延を測れない |
| batch内のRawはService/PID順で追記 | adapterからの実際の応答到着順を保持しない。sequenceは保存処理順 |
| CAN headerをRawへ保存していない | 同一Service/PIDを異なるECUへ送る定義の来歴をRawだけで区別できない |
| evaluatorがmin/maxを適用しない | finiteだが定義範囲外の値を現在は数値化成功として扱う |
| 取得時のapp version、schema version、polling policy、PID capability/collection設定snapshotがない | データ生成条件の世代差や収集選択変更を説明しにくい |
| 取得元の安定installation IDがない | 同platform内の端末差・adapter差を分離できない。端末名の利用は避ける必要がある |
| 距離source enumを保存しない | 標準A6とPID 31の採用元をセッション概要だけで区別できない |
| セッション開始とRaw取得開始が同義でない | `endedAt-startedAt` は取得時間を過大評価し得る。Raw min/maxを併記すべき |
| local DBのCloud状態はremote存在証明ではない | `uploaded` でもProduction Assetの現存・復元成功を別検証する必要がある |
| 車両未関連セッションが許容される | 登録車両モデルへ使用できず、原因別に除外する必要がある |
| interrupted理由とユーザーreviewが別 | `status`だけでなく保存済みend reasonとreview decisionを分離集計する必要がある |

`ConnectionSessionVehicle` には接続時点のVINまたはOBD由来表示値が保存されるため、DB自体は機微情報を含む。学習入力に不要であり、抽出時に列ごと除外する。

## 10. 工程3で測定すべき項目

工程3は対象実車を混在させず、セッション・時間単位の集計として次を測る。

1. 車両ラベル別のセッション数、観測開始日・終了日、記録日数、終了理由、取得platform。
2. `recordedDistanceKilometers` が成立する件数、成立しない理由、合計距離。Raw上の距離PIDとの整合も別集計する。
3. `endedAt-startedAt` とRaw `max(observedAt)-min(observedAt)` の両方の取得時間、および差分。
4. セッション別Raw件数のmin、p10、median、p90、p95、max、IQR。極端に短いセッションを明示する。
5. Service/PID別件数、観測セッション率、観測日率、車両別対応範囲。
6. `numericFinite`、`missingDefinition`、`unavailableFormula`、`insufficientBytes/invalidExpression等`、`nonFinite`、`outOfDeclaredRange` の排他的件数。
7. PID別連続観測の間隔分布（median、p90、p95、p99、max）と、`max(10秒, 3×median)` 等の候補をまだ確定せず比較する長gap件数。
8. 推定batch別の間隔と `batchElapsedNanoseconds` 分布。ただしPID個別latencyとして扱わない。
9. セッション中に一度でも取得されたPIDと、取得後に途切れたPID。要求分母がないため「非応答率」ではなく「観測coverage」と表記する。
10. local state別件数、Cloud state別件数、Manifest有無。実際のオンデマンド復元成功件数はProduction実機試験として別に測る。
11. user disconnected、vehicle no response、connection lost、acquisition failed、superseded、sign-out、unexpected termination、およびreview decisionの分布。
12. 実車/DEMO判定根拠。現在DBだけで確定不能な場合はユーザー確認済みsession範囲を別manifestとして与え、推測で分類しない。
13. 確認済み車速・回転数・温度・負荷が存在する場合だけ、候補走行状態ごとの時間・session・日coverage。分類閾値はこの測定後に決める。
14. 1,000 km候補へ到達するまでの日数・セッション数・状態coverageの分布。単一車両の短期データだけで本番閾値を決めない。

## 11. 実車・Production環境で未確認の事項

- 対象実車の登録 `VehicleID` と、対象に含めてよいsession範囲
- 物理端末に存在する製品DBのschema、row count、integrity、WAL状態
- 実車セッションとDEMOセッションを確実に分離できる外部確認情報
- 実車のPID別件数、値域、周期、gap、欠測、変換成功率、走行状態coverage
- Production CloudKitに `ConnectionSessionRawLog` と `ConnectionSessionMetadata` が存在すること
- `removed` RawのProduction Asset download、SHA-256検証、GRDB復元、decode完了
- 取得端末間・アプリversion間のデータ互換性
- 走行距離差分の実車妥当性と、採用された距離source
- 実端末でのRaw総容量、CloudKit Asset容量、転送所要時間

ローカルschema、unit test、Simulator、過去の実装記録は、これらのProduction/実車証拠を代替しない。

## 12. 次に必要な入力と読み取り専用抽出方法

### 12.1 必要なログの取得元

優先順位は次のとおりである。

1. 実車ログを取得したiPhone/iPadの `Ryokugyoku.ProjectZD8` app data container。
2. その端末でlocal Rawが削除済みの場合は、同じAppleアカウントでProduction CloudKitから対象Rawを正規経路で復元したMacのapp data。ただし復元操作はDBを変更するため、この工程の外でユーザーが明示実行する。
3. 既にMacへ同期・復元済みなら、Macの `~/Library/Application Support/ProjectZD8/` のオフライン複製。

CloudKit Dashboardからの手作業export、DEMO DB、test fixtureを実車代替にはしない。

### 12.2 ユーザーに依頼する操作

1. 対象実車と、おおよその対象期間を画面上で確認する。VIN、account ID、`VehicleID` をチャットへ貼らない。
2. local Rawが残る物理端末をMacへ接続し、ロック解除・信頼・Developer Mode等、Apple標準の読取条件を満たす。
3. 一貫したSQLite複製のためProjectZD8を終了する。ログの修復・削除・再収集はしない。
4. Codexへ「端末を接続しアプリを終了した」とだけ知らせる。端末名や識別子は不要である。
5. local Rawがない場合だけ、対象セッションをアプリの通常確認画面からMacへ復元するかを別途承認する。Production CloudKitへ書込みやschema変更は行わない。

### 12.3 読み取り専用の抽出

物理端末では `xcrun devicectl device copy from` を使い、app data container内の `Library/Application Support/ProjectZD8` ディレクトリを、新規のホスト側一時ディレクトリへコピーする。これは端末側を読取り対象とし、出力先を既存データに重ねない。SQLite本体に加えて存在する場合は `projectzd8.sqlite-wal` と `projectzd8.sqlite-shm` も同時に取得するため、単一ファイルよりディレクトリcopyを優先する。

複製後は原本を開かず、さらに作業用copyを作り、次だけを実行する。

```sh
sqlite3 -readonly /path/to/offline-copy/projectzd8.sqlite 'PRAGMA integrity_check;'
sqlite3 -readonly /path/to/offline-copy/projectzd8.sqlite '.schema connection_sessions'
sqlite3 -readonly /path/to/offline-copy/projectzd8.sqlite '.schema connection_session_raw_logs'
```

集計器はparameterized read queryだけを使用し、禁止列をstdoutへselectしない。CloudKit接続、GRDB migration、アプリ起動、write transaction、`VACUUM`、`REINDEX`、`PRAGMA journal_mode`変更は行わない。

### 12.4 必要なファイル、端末、容量

- 必須: `projectzd8.sqlite`。
- SQLiteが使用中だった可能性がある場合: 同じ時点の `projectzd8.sqlite-wal` と `projectzd8.sqlite-shm`。最も安全なのはアプリ終了後のProjectZD8 Application Supportディレクトリ一式。
- 必須端末: 実車ログを取得しlocal Rawを保持するiPhone/iPad、または復元済みMac。
- 空き容量: コピー元Application Supportディレクトリの実サイズの2倍に、解析出力用1 GiBを加えた容量を確保する。Raw概要の `rawByteCount` はpayload byteだけで、SQLite index、row、WAL、JSON転送overheadを含まないため容量見積りに単独使用しない。
- 容量確認値も合計byteだけを報告し、ファイル内容や識別子は表示しない。

### 12.5 工程3へ進むために不足している証拠

- 読取専用offline DB copyの `integrity_check=ok`
- schema列がこの文書の想定と一致すること
- account scopeを混ぜず、対象登録車両が実車であるというユーザー確認
- 対象車両に1件以上の終了済みsessionと1件以上のRaw行があること
- local RawがないsessionについてはProduction CloudKitからの復元成功、または利用不能という確定結果
- PID definition tableとRawを同じsnapshotから取得し、現行revisionと件数を固定できること
- 匿名集計が禁止列・Raw payloadを出力しないことのreview

これらが揃えば工程3のデータ品質測定へ進める。揃う前に特徴量、走行状態閾値、1,000 km閾値、スコア方式、モデル方式を確定してはならない。
