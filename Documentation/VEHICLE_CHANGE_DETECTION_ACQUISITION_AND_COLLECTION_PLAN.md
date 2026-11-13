# 登録車両専用変化検知 取得証跡・追加収集・再測定計画

## 1. 文書の責務と現在の判定

本書の責務は、登録車両専用変化検知に向けて、(a) 初版データモデル(`insight-v1`)が取得時の生成条件をどこまで再現できるか、(b) 何が未解決か、(c) 追加の実車ログを受領するたびに匿名・読み取り専用でデータ品質を再測定する契約、を互いに独立して定義することである。

本書は設計・収集・測定計画であり、Production CloudKitへの接続、物理端末データの変更、実車での取得、UI変更、MLX依存追加、学習、推論を承認しない。

データモデルの前提(決定済み):

- 後方互換は持たない。旧 `projectzd8.sqlite`(`connection_sessions`、`connection_session_raw_logs`、`obd_pid_definitions`、`connection_session_acquisition_*` 取得証拠表)と旧CloudKitレコードは読まない。新しい保存先は `Application Support/ProjectZD8/insight-v1.sqlite` の1ファイルで、スキーマは `AppDatabaseMigrator` の `v1` が唯一である。
- Rawログは `session_samples` の追記専用1表に統一した。無応答を含む要求1件につき1行で、旧Raw表と、別表だった取得batch / 要求証拠を置き換える。
- PID定義はDB表ではなくコード同梱カタログ(`Domain/Catalog`)で、各セッションが取得時点の複写を `session_pids` に持つ。
- アプリ独自のログインとアカウント識別子は存在しない。データは端末のiCloudアカウントに属し、セッションは常に車両に属する。

現在の判断は次のとおりである。

- **新データモデルによる実車ログはまだ1件も存在しない。** 2026-07に旧スキーマで行った実車監査([`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md))のデータ(8 session、2記録日、37.0 km、Raw 60,505件、35 PID)は新スキーマへ引き継がれない。監査の方法と所見は設計の参考として残るが、データ量・coverageとして数えない。
- 旧実装で行った取得証拠保存のsynthetic性能測定、Production配線結果、実機性能測定計画(旧Phase 4F〜4I)は旧表構造に対するものであり、新実装には適用できない。結果は引き継がず、新実装に対する測定は §8 Phase 4 で別途計画する。
- 現データの学習入力とPrompt CのMLX feasibility spike実装は引き続き **`no-go`** である。データモデルの改善だけでは解除しない(§9)。

根拠表記は次を使う。

| 区分 | 意味 |
| --- | --- |
| `requirementDerived` | 要件から直接導かれる不変契約 |
| `currentImplementation` | 本書時点のソース(Domain、`AppDatabaseMigrator`、`CLAUDE.md`)で確認した設計・実装上の事実 |
| `realDataObserved` | 匿名実車監査で確認した記述的事実(旧スキーマ、新データモデルでは未取得) |
| `candidate` | 後続phaseで比較・承認する案。Production確定ではない |
| `blocked` | 現在の証拠では決定、分類、または実行できない |

## 2. 現実装から導く設計境界

| 現在の事実 | 設計への含意 | 区分 |
| --- | --- | --- |
| `session_samples` は `(sessionID, sequence)` 主キーの追記専用表で、UPDATEをトリガーで禁止する | 要求の分母、結果、順序は行そのものから再現できる。Raw行を後から書き換えない | `currentImplementation` |
| `outcome` は `responded` / `noData` / `timedOut` / `failed` の4値で、無応答行の `payload` は空 | PIDごとの応答率は `responded` 行数 / 全行数。分母を別表から推測しない | `currentImplementation` |
| `tick` と `elapsedMicroseconds`(セッション開始からの単調時計)を各行が持つ | 取得周期、tick内の要求順、tick間隔を壁時計に依存せず測れる | `currentImplementation` |
| `session_pids` はセッション開始時点のPID条件(式、必要バイト数、単位、範囲、定義改訂、対応状況、収集有無、高頻度グループ、CANヘッダー)を追記専用で保持する | 分析は必ずこの複写で復号する。後からカタログを改訂しても取得時の規則で再解釈できる | `currentImplementation` |
| `sessions` は app version / build、platform、deviceID、deviceName、adapterName、adapterTransport、pollingPolicyVersion、isDemo、距離source、集計列を持つ | 取得条件のcohort分離とdemo除外ができる | `currentImplementation` |
| `AcquisitionPollingPolicy` は高頻度グループを毎tick、その他を1tickあたり `slowRequestsPerTick` 件ずつ巡回して選ぶ。版は `AcquisitionPollingPolicy.version` | 選択規則は版で識別するが、`slowRequestsPerTick` の値そのものは保存しない(版1の既定値は2)。実際の選択結果は各tickの行から直接観測できる | `currentImplementation` |
| セッションの全内容は `SessionArchive`(`formatVersion` 付き)として圧縮アーカイブ化し、終了後に1回iCloudへアップロードする。`archiveDigest` と `rawAvailability`(`local` / `cloudOnly`)で状態を持つ | 別端末や端末内Raw解放後の再解析の経路が定義された。ただしProductionでの現存・復元は未検証 | `currentImplementation` |
| デモセッションは `isDemo` 付きで記録し、同期しない。PID収集設定(`vehicle_pid_settings`)も同期しない | 学習・品質集計の分母からdemoを機械的に除外できる | `currentImplementation` |
| 分析はアプリ同梱のHTML/JavaScriptワークベンチ(WebView)で、Swiftが復号済みデータセットを渡す | 取得・保存経路と分析表示を分離でき、Raw保存を分析の都合で書き換えない | `currentImplementation` |

依存方向は `Platform -> Application -> Domain <- Data` とし、Appが構築する。View、iOS/macOS layout、ML runtimeは本計画の保存経路に参加しない。

## 3. 取得時metadata

### 3.1 論理構造

取得時の生成条件は次の2層で保持する(旧計画の3階層manifestからbatch層を除き、要求行へ統合した)。

1. `sessions` 1行: 取得環境・policy・集計・終了状態。
2. `session_pids` N行: セッション内の順序付きPID集合。各PIDの取得時の意味と復号規則を固定する。

要求結果は `session_samples`(§4)に置く。`session_pids` と `session_samples` は追記専用で、`sessions` の可変列は終了情報と集計列(`endedAt`、`endReason`、距離、件数、`rawAvailability`、`archiveDigest`、`modifiedAt`)に限られる。

`model input manifest` は将来のモデル世代が持つ契約であり、取得証跡には含めない `[requirementDerived]`。

### 3.2 要件別の充足状況

初期監査(旧スキーマ)で不足と記録した項目と、`insight-v1` での扱いは次のとおりである。

| 要件・旧不足 | `insight-v1` での保存先 | 状態 |
| --- | --- | --- |
| 取得時PID definition revision | `session_pids.definitionRevision` | 設計上充足。実取得データでの確認は未実施 |
| formula、required byte count、unit、validity range | `session_pids.formula` / `requiredByteCount` / `unit` / `minimumValue` / `maximumValue`(式そのものを複写するため改訂番号だけに依存しない) | 設計上充足 |
| 要求の分母・無応答・timeout | `session_samples` の全要求行と `outcome` | 設計上充足。実取得での確認は未実施 |
| ordered requested PID set | `session_pids.ordinal` 順 | 設計上充足 |
| PID capability / collection snapshot | `session_pids.support` / `isCollectionEnabled` / `isFastGroup` | 設計上充足。`support` は `supported` / `unsupported` / `unknown` の3値で、`unsupported` に至る証拠の種類は保存しない |
| polling policy version | `sessions.pollingPolicyVersion`(`slowRequestsPerTick` は版から導く) | 部分充足。巡回件数の値は保存しない |
| app version / build | `sessions.appVersion` / `appBuild` | 設計上充足 |
| schema version | マイグレーション履歴(`grdb_migrations` が `v1`)と `SessionArchive.formatVersion` | 部分充足。セッション行自体にはschema版を持たない |
| acquisition platform | `sessions.platform`(`iPhone` / `iPad` / `mac`) | 設計上充足 |
| DEMO区分 | `sessions.isDemo` と `adapterTransport = demo` | 設計上充足 |
| adapter / transport | `sessions.adapterName`(個体を示す文字列を含み得るため出力しない)、`adapterTransport`(`bluetoothLowEnergy` / `bluetoothClassic` / `usbSerial` / `demo`) | 部分充足。adapterのfirmwareと確立したOBDプロトコル(ELMの `ATDP` 相当)は保存しない |
| CAN header | `session_pids.header`(PIDごと、セッション内で固定) | 設計上充足。要求行単位のheaderは保存しない(同一セッション内で同じService/PIDに複数headerを使えない) |
| tick | `session_samples.tick` | 設計上充足 |
| 取得元installation ID | `sessions.deviceID`(インストール単位。出力しない) | 設計上充足。cohort比較は匿名ラベルへ縮約して行う |
| 距離source | `sessions.distanceSource` | 設計上充足 |
| Raw取得開始・終了の実時間 | `startedAt` / `endedAt` と各行の `elapsedMicroseconds` | 設計上充足。session時間とRaw観測時間の差を行から計算できる |
| Raw保存の再現性 | `sessions.sampleCount` / `respondedCount` / `payloadByteCount` と行の整合 | 設計上充足。整合検査は集計器が行う(§7) |

### 3.3 未解決・限界

次は `insight-v1` でも保存されない、または保存の意味が未確認であり、`blocked` として残す。

- **PID個別の応答遅延**: `elapsedMicroseconds` が要求発行時刻か応答受信時刻かは、Logging実装で確定するまで本書では断定しない。どちらの場合も、要求から応答までの時間と応答の到着順は別の値としては保存されない。
- **`noData` と `failed` の内訳**: ELM/STNのエラー文字列、負応答コード(NRC)、CANレベルの失敗は区別しない。
- **adapter firmware / 確立プロトコル**: 保存しない。cohort比較には使えない。
- **polling巡回件数の値**: 版1の既定値が変わらない限り再現できるが、値を変えた場合は版を上げる運用が必須である。
- **車両側の状態**: 走行状態、ブレーキ等は保存しない。状態は取得済みPIDからの導出に限る。
- **formula評価系の版**: 制限付き式の評価規則が変わった場合の版は保存しない。式の文法を変える場合は `definitionRevision` を上げる規約に依存する。
- **実機での検証**: 上表の「設計上充足」は、ソースとスキーマの設計を確認した結果であり、実アダプター・実車・複数端末での記録内容を確認したものではない。

### 3.4 privacy、同期、保持

- `deviceID`、`deviceName`、`adapterName`、VIN、`VehicleID`、session ID、`archiveDigest`、Raw payload は匿名成果物とmodel featureへ出さない。`adapterTransport`、`platform`、`appVersion+appBuild`、`pollingPolicyVersion` は匿名ラベルとして集計できる。
- 同期はCloudKitプライベートDBの専用ゾーンに、セッションを `SessionArchive` として終了後に1回アップロードする。iCloud未サインインでも取得・記録・分析は端末内で動く。local保存成功をCloudKit同期成功と扱わない。
- Rawが端末から解放された(`rawAvailability = cloudOnly`)セッションは、再解析前にiCloudから復元する必要がある。復元成功は別証拠として検証する(§9)。
- セッション削除時は、同期済みなら `deletedAt` を入れて同期へ渡し、未同期なら物理削除する。孤立した `session_pids` / `session_samples` は外部キーのcascadeで残らない。

## 4. 要求・非応答の記録

### 4.1 単一表モデル

Raw payloadと要求結果を1つの追記専用表で保持する。旧計画で比較した方式A〜D(Raw行拡張、manifest＋batch表＋request表、blob、推定)のうち、実質的に「要求ごとに1行、無応答も行を持つ」方式を採用した形である。

```text
sessions
  ├─ session_pids   (ordinal順の取得時PID条件)
  └─ session_samples (sequence順、要求1件=1行)
        tick / elapsedMicroseconds / service / pid / outcome / payload
```

要求結果は1軸 `outcome` で保持する。

| outcome | 意味 | payload |
| --- | --- | --- |
| `responded` | データ付き応答 | 非空 |
| `noData` | 車両が NO DATA と応答 | 空 |
| `timedOut` | 応答待ちがタイムアウト | 空 |
| `failed` | 応答を解釈できない、または通信エラー | 空 |

PIDごとの要求数は行数であり、応答率は `responded` / 行数である。`unsupported` は `session_pids.support` の取得開始時点の事実であり、`outcome` の値ではない。`noData` を `unsupported` へ変換しない。応答なしを0へ置換しない。値の復号結果(有限値、範囲外など)は行へ保存せず、`session_pids` の複写から都度導く。

### 4.2 限界

- 1 tickで要求しなかったPID(巡回で選ばれなかった低頻度PID)は行を持たない。意図的な省略かどうかは、`pollingPolicyVersion` が示す規則と `session_pids` の集合から導く。
- 記録中にアプリが終了した場合、次回起動時に `endReason = appTerminated` で閉じる。終了時に未確定だった要求の結果は行として保存されない(未確定要求を別の `outcome` へ補正しない)。
- 取得または保存の失敗は `endReason = acquisitionFailed` として記録し、成功した取得へ変換しない。
- `sequence` は要求の記録順であり、応答の到着順を保証しない(§3.3)。

## 5. 追加実車ログ収集計画

### 5.1 collection batchの定義

本節の`collection batch`は、OBDの要求batchではなく、前回匿名測定後に自然な利用で追加された終了済みsession集合である。必要日数、距離、session数を事前固定しない。新スキーマで最初に取得できた終了済み実車session集合を `B0` の記述的基準とし、以後 `B1`、`B2` のような成果物内だけのordinalで比較する。旧スキーマの8 sessionは `B0` に含めない。原session IDや正確な個別時刻は出力しない。

各collection batchは次の両方で測る。

- incremental: 今回新たに追加されたsessionだけ。新規条件が増えたかを見る。
- cumulative: B0から今回まで。分布とsplit成立性が安定へ向かうかを見る。

batchの終了は固定距離でなく、通常利用で新しい記録日、session長、時間帯、状態候補、app/policy/platform cohortのいずれかが増えた時点を候補とし、人間が再測定単位を承認する。収集のために危険運転、意図的な高負荷、交通法規違反、不要な長時間idleを要求しない。high-loadは通常の安全運転で自然に実在した候補だけを測る。

### 5.2 batchごとの収集軸

| 軸 | incrementalで記録 | cumulativeで比較 | 注意 |
| --- | --- | --- | --- |
| 追加記録日 | 行があるdistinct UTC日数 | 記録日の増分と期間幅 | 個別走行時刻は出さない |
| 追加距離 | 成立sessionの距離合計と不成立理由 | 合計距離と成立率 | `distanceSource` 別に併記 |
| 終了済みsession | `endReason` 別件数 | 独立session数 | 記録中のsessionは品質分母から除外 |
| 短/長session | 行数・Raw観測時間の分位帯別件数 | 各帯のwindow成立率 | 固定秒数で先に除外しない |
| 異なる走行時間帯 | local処理内の粗いversioned bucket件数 | bucket間coverage | timezone、bucket境界は別承認。正確な時刻を出さない |
| idle / low-speed / cruise | 候補gridごとのwindow、時間、session、日、距離 | support再現性 | 閾値をProduction確定しない |
| acceleration / deceleration | slope候補ごとの同じcoverage軸 | 符号・持続候補の再現性 | 急操作を依頼しない |
| warm-up / warmed | 確認済み温度/runtime候補のcoverage | 開始時点とplateau候補の再現性 | cold-startを時刻だけで推測しない |
| high-load候補 | 通常走行中に自然発生した候補coverage | session/日への分散 | 意図的な高負荷取得は禁止 |
| PID coverage | PID別の要求session数・応答session数・応答率 | ordered setの再現性 | 要求分母は行数から得る |
| cadence | PID別の要求間隔・応答間隔・tick間隔分布 | cohort内・batch間の分布差 | policy cohortを混ぜない |
| gap候補 | 固定/相対候補別件数とwindow影響 | gap mask分布 | timeoutと呼ばない(timeoutは `outcome`) |
| app version差 | `appVersion+appBuild` cohort別の全品質metric | cohort間差 | 取得後すぐ分類できる |
| polling policy差 | `pollingPolicyVersion` と `session_pids` 集合のcohort別metric | 同一policy内安定性とpolicy間差 | |
| acquisition platform / transport差 | `platform` / `adapterTransport` 別metric | platformごとのsupport | 端末名・IDは使わない |
| 整備前後period | 実在し人間確認済み境界の前後を分離 | 混入なしの記述比較 | 整備効果・因果を推測しない |

狙った状態を作る走行指示はしない。収集後に「自然に含まれていたか」を匿名測定し、不足状態は`insufficientCoverage`として残す。必要量は、複数collection batchでcoverage、分布、split可能性が安定するかを見てから提案する。

## 6. 各collection batch後の再測定契約

### 6.1 毎回同じ手順で測る項目

各batch後は、[`VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md`](VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md)の原本/snapshot/working copy、`mode=ro`、privacy、deterministic JSON契約を再利用する。計算versionを出力へ明示し、同じversionの結果だけを直接比較する。

| 測定項目 | 最小出力 | 判定上の扱い |
| --- | --- | --- |
| window候補ごとの成立数 | window長/overlap/alignment候補別の成立・不成立件数と理由 | 候補を採用しない |
| PID別valid observation count | Service/PID、window/session/day別の有限範囲内件数 | 要求数(分母)と分離 |
| missing mask分布 | mask cardinality、PID別missing率、匿名集約pattern頻度 | 0補完しない。rare pattern出力はprivacy承認対象 |
| gap mask分布 | 候補別mask cardinality、最大gap、影響window数 | `timedOut` と読み替えない |
| session長別coverage | Raw時間/sample数quantile帯ごとのwindow成立率 | 特定長sessionの支配を検出 |
| 状態候補別coverage | window、時間、session、日、距離の5軸 | いずれかを他の代用にしない |
| split成立性 | train/validation/testへ割当可能な独立session数、日数、時間範囲、各状態support | Raw行random splitを禁止 |
| PID coverage再現性 | incremental/cumulative、cohort別session/day/window coverage | `session_pids` 集合が一致するcohort内で比較 |
| cadence安定性 | PID/cohort別interval median、IQR、分位点 | session/batchを跨ぐintervalを作らない |
| gap安定性 | 候補別件数率、window不成立率、分布 | policy/version差を分離 |

missing maskのpattern histogramは内部計算できるが、PIDの稀な組合せは車両fingerprintになり得る。外向けJSONは、PID別率、mask cardinality分布、privacy上承認された最小supportを満たす集約patternだけを出し、それ未満は決定的な`otherSuppressed`へまとめる候補とする。support値はprivacy review前に固定しない。

状態候補はFeature Spec §6の候補gridをversioned入力として使い、閾値ごとに別結果を出す。PIDが存在するだけで状態成立としない。`unclassified`と理由を保持する。

### 6.2 split成立性

split候補はsessionを最小groupとし、時間順のtrain→validation→testを崩さない。同一session、同一走行、重複window、同じsource intervalを複数splitへ入れない。整備periodが実在する場合は境界を跨いでreferenceへ混ぜない。

各候補splitについて、IDを出さずに次を報告する。

- 各splitの独立session数、記録日数、Raw観測時間幅、距離成立分の距離。
- 各splitのPID、状態、window、missing/gap support。
- validation/testがtrainより後の時間範囲にあるか。
- 特定1 sessionがwindow、状態、距離の大半を占めるか。
- split不能理由: `insufficientIndependentSessions`、`insufficientTimeSeparation`、`stateCoverageMissing`、`manifestCohortMismatch`、`maintenanceBoundaryUnknown`等。

新データモデルのsession量は未取得であり、十分性の閾値は複数batchの測定後まで確定しない。

### 6.3 前batchとの差と安定判定候補

採用方式・数値閾値は本書で固定しない。同一calculation version、同一cohort、同じ候補定義について、次を並列に比較する。

| 比較候補 | 対象 | 注意 |
| --- | --- | --- |
| median / IQR差 | cadence、gap、window内count、session長 | 尺度差を併記する |
| p10 / p50 / p90 / p95 / p99差 | cadence、gap、coverage、状態滞在 | tailの少数支配を確認する |
| Wasserstein distance候補 | 連続分布 | sample数差に対する解釈を事前固定する |
| KS statistic候補 | 連続経験分布 | p-valueだけで安定を決めない |
| Jensen-Shannon distance候補 | mask/state等の離散分布 | zero cellとbucket versionを固定する |
| bootstrap confidence interval | median、率、分布距離、状態support | resample単位はRaw行でなくsession、必要ならday cluster候補 |
| rank/candidate stability | window/state/gap候補の順位 | batch追加で順位反転するなら`revise` |

安定は単一metricの閾値通過ではなく、少なくとも複数の独立collection batchで、supportが増え、CIが狭まり、主要候補の順位が大きく反転せず、特定sessionへの集中が低下し、split全区画でrequired coverageが成立することを人間が確認する候補とする。何batch連続、どのCI幅、どの分布距離を採用するかは実測後の承認事項である。

## 7. offline集計器

### 7.1 現状

`Tools/VehicleChangeDataQuality/` は新スキーマ(`insight-v1`)だけを読む。`sessions` / `session_pids` / `session_samples` の列とマイグレーション履歴を完全一致で検査し、旧スキーマを拒否する。出力契約・計算・スキーマのversionは2である。実装済みの集計は次である。

- 各セッションの `session_pids` 複写による数値変換分類(7種の排他的分類)と、複写された定義改訂の分布。
- PIDごとの要求数、`outcome` 別件数、応答率、要求間隔・応答間隔・tick間隔の分布、long gap候補別件数、観測session率・観測日率。
- セッション集計列とRaw行の整合、`elapsedMicroseconds` / `tick` の単調性、PID snapshotの欠番、無応答行のpayload有無などの品質検査。
- `isDemo` セッションは `demo` と明示分類した場合のみ集計し、それ以外は除外件数だけを出す。アカウント階層はscope manifestから除いた。

fixture testは合成DBだけで行い、実車データを使わない。

### 7.2 拡張が必要な項目(未実装)

現集計器は、window候補、missing/gap mask、状態候補、split成立性、collection batch差を集計しない。次を拡張候補とし、現在の匿名結果を上書きせずcontract versionを上げた別結果として追加する。

- collection batch ordinal、incremental/cumulative区分、app/policy/platform/transportの匿名cohort。
- window候補別の成立/不成立理由、PID別valid observation count、missing/gap maskの安全な集約分布。
- session長quantile帯、状態候補別のwindow/時間/session/日/距離coverage。
- session/time split候補の成立性と匿名reason。
- 前batchとのmedian/IQR、分位点、分布距離、bootstrap CI候補。採用判定は出力しない。

### 7.3 privacy、read-only、決定性、不変性の契約

- VIN、`VehicleID`、session ID、`deviceID`、`deviceName`、`adapterName`、`archiveDigest`、Raw payload、個別走行時刻、個別時系列を出力しない。
- formula文字列、private scope manifestも外向けJSONへ出さない。
- timestampは内部計算後に日数、期間幅、粗い承認済み時間帯bucketへ縮約する。
- session別・window別行は出力せず、分布と件数だけを出す。rare mask/cohortは決定的に抑制する。
- SQLiteはURI `mode=ro`、`query_only=ON`、`trusted_schema=OFF`で開き、コード内の固定SELECTだけを使う(ツールが強制する)。実行前後のfile set・SHA-256・size・mtimeの一致確認は運用手順の責務であり、ツールは検証しない。
- 同じsnapshot、scope manifest、計算設定、tool versionからbyte-for-byte同じcanonical JSONを生成する。
- 同一入力で2回生成したJSONのSHA-256が一致し、privacy validatorが合格しなければ文書へ転記しない。

### 7.4 拡張時の変更候補

| ファイル候補 | 単一責務 |
| --- | --- |
| `Tools/VehicleChangeDataQuality/collection_measurement.py`(新規) | Raw時系列からwindow/mask/state/split候補の匿名集計を作る |
| `Tools/VehicleChangeDataQuality/collection_comparison.py`(新規) | 2つの互換匿名報告からbatch間差とCI候補を作る |
| `Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py` | CLI入力を検証し各責務を呼び出す(optional previous report) |
| `Tools/VehicleChangeDataQuality/privacy_validation.py` | 拡張JSONの禁止情報とrare出力契約を検証する |
| `Tools/VehicleChangeDataQuality/Tests/` | 上記のsynthetic fixture test(短/長session、gap、missing、状態候補、整備period分離、同一seed一致、cohort不一致拒否) |

新規fileは既存の`Tools/VehicleChangeDataQuality/`と`Tests/`内にだけ置き、製品Swift、Xcode target、GRDB package、CloudKit、MLXへ依存させない。新directoryは作らない。fixture成功は実車量、実車状態coverage、Production性能、CloudKit動作を証明しない。

### 7.5 実行コマンド

```sh
PYTHONPATH=Tools/VehicleChangeDataQuality \
  python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v

python3 Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py \
  --database "$PROJECTZD8_WORK_DB" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json" \
  --output "$PROJECTZD8_CAPTURE_ROOT/anonymous-data-quality.json"

python3 Tools/VehicleChangeDataQuality/validate_anonymous_output.py \
  --report "$PROJECTZD8_CAPTURE_ROOT/anonymous-data-quality.json" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json"
```

実snapshotを分析する場合は、変更前に人間へ対象snapshot、対象範囲、出力予定の匿名項目、保持場所を提示し、明示承認を得る。実行前後にsnapshot/working copy双方のhash、size、mtime、file setを比較し、同一入力を2回実行して同一JSONを確認し、privacy validatorでVIN、`VehicleID`、session ID、端末名、Raw payload、個別走行時刻が0件であることを確認する。本書の作成時点で、新スキーマの実snapshotを分析した実績はない。

## 8. Production変更を分離するphase

各phaseは前phaseの成果物を入力とするが、承認と受入は独立させる。旧計画のmanifest/batch/request表のDomain・GRDB・migration phaseと、旧DBからの移行・旧session互換性・rollback phaseは、新スキーマが取得証跡を最初から含み後方互換を持たないため削除した。

### Phase 1: Domain・スキーマ(ソース実装済み)

- 対象: `Domain/Entities/{DriveSession,SessionPID,SessionSample,SessionArchive}.swift`、`Domain/Catalog`、`Data/Persistence/GRDB/Database/AppDatabaseMigrator.swift`。
- 受入条件: 要求単位の行、取得時PID条件の複写、追記専用トリガー、`isDemo`、集計列の整合が単体testで成立する。
- 状態: ソース上の設計は存在する。単体testの網羅と実機検証は本書では主張しない。

### Phase 2: Loggingによる証跡記録

- 対象: `Application/Features/Logging`(接続→車両識別→セッション開始→ポーリング→保存→終了)と `AcquisitionPollingPolicy`。
- 受入条件: 取得開始前に `session_pids` が確定し、全要求が(無応答を含め)行として保存され、`tick` / `elapsedMicroseconds` が単調で、保存失敗が成功取得として扱われず、終了理由が正しく記録される。
- 未確認: `elapsedMicroseconds` の測定点(§3.3)、保存失敗時のbackpressureと後続要求の扱い、アプリ終了時の回復。
- 人間承認: 失敗方針(Raw優先)、測定点の定義。

### Phase 3: アーカイブ・同期

- 対象: `SessionArchive` の生成・検証、`Data/Sync/`(CloudKit)、`rawAvailability` の遷移、Raw解放と復元。
- 受入条件: アーカイブの `formatVersion`、digest、`session_pids` / `session_samples` 整合を検証し、未知versionを拒否し、復元がatomicで、デモを同期しない。
- 未確認: CloudKitのrecord/Asset構成、容量、Production schema、retention/deletion連鎖。
- 人間承認: CloudKit data model、Development検証範囲。Production schema変更とProduction接続はさらに別承認。

### Phase 4: 新実装に対する取得性能・容量の測定

- 旧Phase 4F〜4Iの測定結果と実機測定計画は旧表構造のものであり引き継がない。新実装では「無応答を含む1要求1行」の追記コスト、DB/WAL容量、取得loopの遅延、バッテリー・thermal、バックグラウンド、アプリ終了時回復を、対象端末・adapter・transport・bench/車両・Release相当buildを人間が固定してから測る。
- 受入条件: 数値budgetと停止条件を測定前に固定し、測定結果をrepository外の制限付きartifactと匿名集計に分ける。synthetic測定の結果を実機性能として扱わない。
- 状態: 未計画。対象と予算は人間未決定であり、実機・実adapter・実車への接続は本書では承認しない。

### Phase 5: offline集計器拡張

- 変更候補: §7.4の`Tools/VehicleChangeDataQuality/`内だけ。
- 受入条件: window/mask/state/split/batch比較を匿名JSONへ決定的に出す。
- 人間承認: 匿名出力契約、候補grid、実snapshot再分析範囲。

### Phase 6: synthetic fixture test

- 変更候補: §7.4のTestsだけ。OS一時directoryとPython標準ライブラリだけを使う。
- 受入条件: 全outcome、window/mask/state/split、privacy、read-only、determinism、スキーマ拒否を網羅する。

### Phase 7: 実端末・実車での受入

- 通常の取得経路だけを使い、安全な通常走行でセッション→Raw→終了→(同期)→offline再測定が一致することを確認する。
- 未確認: 実車での `outcome` の分布(`noData` / `timedOut` / `failed`)、background/切断、platform差、長期量、複数端末での同期。
- 人間承認: 実車実施範囲、端末、通常走行条件、ログ取得・保持・削除判断。

### スキーマ変更方針

リリース後のスキーマ変更は新しいマイグレーションとして追加し、既存セッションの `session_pids` / `session_samples` を書き換えない。互換性のない変更は新しいファイル名(例 `insight-v2.sqlite`)へ切り替える `AppDatabase.fileName` の規約に従い、旧データの扱いを別途合意する。

## 9. blocked事項とPrompt C解除条件

### 9.1 blockedのまま残す事項

- 新データモデルによる実車ログの量(現在0件)。必要日数、距離、session数、window数、状態coverageのProduction閾値。
- 旧スキーマ監査のデータは新スキーマへ引き継がれず、その量と所見を新データモデルの証拠として数えない。
- window長、overlap、resampling、carry-forward、gap、missing処理の採用方式。
- idle、low-speed、cruise、acceleration、deceleration、warm-up、warmed、high-loadのProduction閾値。
- statistical baseline、distance方式、autoencoder、score、confidence、persistence、system mapping。
- app/policy/platform/transport差の互換性と、整備前後の効果・因果。
- 新実装の取得性能、保存容量、battery、CloudKit転送量。
- Production CloudKit Assetの現存、復元、schema、TestFlight/実端末動作。
- §3.3の項目(PID個別応答遅延、`noData` / `failed` の内訳、adapter firmware等)。

### 9.2 Prompt Cへ進むための具体的解除条件

次をすべて別証拠として満たすまでPrompt CのMLX feasibility spike実装へ進まない。

1. **新データモデルで取得したセッション**について、各使用PIDの取得時definition revision、必要バイト数、式、単位、範囲、ordered set、policy版、要求結果(`outcome`)を `session_pids` / `session_samples` から再現できることを、実機・実adapter・実車の取得データで確認する。ソース上の設計だけでは解除しない。
2. 旧スキーマで取得した実車ログは新スキーマへ移行しない。旧ログから学習する場合は、本書とは別に人間が承認する明示的な経路が必要で、現時点ではその経路は存在しない。
3. Phase 5〜6の匿名集計器がwindow候補、状態候補、missing/gap、split、batch比較を決定的に測定し、privacy validatorとsnapshot/working copy不変性が合格する。
4. 追加collection batchにより、独立したsession/time train・validation・test候補が各required PID/状態のsupportを持ち、同一session/重複window leakageなしで成立する。
5. 複数batchでPID coverage、cadence、gap、mask、状態coverageの分布とCIを比較し、人間が事前に選んだ安定基準を満たす。基準値はtest結果を見る前に固定する。
6. ML比較のprimary metric、guardrail、seed、停止条件、resource測定対象をtest splitを見る前に承認する。
7. Prompt C固有のMLX ownership、dependency、production/test path、新folder/standards変更について別のapproval gateを通過する。

データモデル実装だけ、追加距離だけ、fixture成功だけ、window成立数だけでは解除しない。解除後も意味はfeasibility比較の開始許可であり、モデル精度、故障検知、実車妥当性、Production/CloudKit動作の承認ではない。

## 10. 次に人間が承認すべき最小phase

最小の次段階は、新実装(Phase 1〜3)を通常のビルドとして実機で動かし、**対象を固定した安全なbench(実車配線を使わない規格適合ECU simulatorなど)または承認済み車両の通常利用**で数セッションを記録して、取得証跡が設計どおり保存されること(全要求行、無応答の `outcome`、`tick` / `elapsedMicroseconds`、`session_pids` 複写、集計列の整合)を、本書の集計器で匿名確認することである。

人間は少なくとも次を確認する。

- 対象platform、端末、Release相当build、署名・配布経路。
- 資料と実物で確認済みのadapter、transport、benchまたは車両条件。
- `elapsedMicroseconds` の測定点と、保存失敗時のRaw優先方針。
- 数値budget(性能、容量、battery、thermal)を測定前に固定すること。
- repository外artifactの保存先、アクセス権、保持期間、削除責任、匿名JSONだけをrepositoryへ置くかどうか。
- 最初の承認を、接続前sanityと短時間のbench記録までに限定すること。実車、反復・耐久、background、CloudKit Production、一般リリースは別gateとする。

## 11. 証拠境界

本書と後続のfixtureは設計・計算契約の証拠に限る。次は常に別々に報告する。

- source/static checkとunit test
- synthetic fixture
- offline snapshot不変性とprivacy validator
- 物理端末copyと実車ログ量(新データモデルでは未取得)
- 実車での要求結果分類と取得性能
- Production CloudKit schema、Asset現存、復元
- hosted CI、TestFlight、UI、human review
- model学習、held-out精度、実車妥当性

いずれかの成功を他の成功として扱わず、未確認PID、故障、劣化、整備効果を推測しない。ローカルのビルド・テスト成功を、見た目・実機・実アダプター・CloudKit本番・CIの成功として報告しない。
