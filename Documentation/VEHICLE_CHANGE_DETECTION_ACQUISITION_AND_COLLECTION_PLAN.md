# 登録車両専用変化検知 取得metadata・追加収集・再測定計画

## 1. 文書の責務と現在の判定

本書の責務は、登録車両専用変化検知の次工程に向けて、将来取得分の生成条件を再現するmetadata保存候補と、追加実車ログを受領するたびに匿名・読み取り専用でデータ品質を再測定する契約を、互いに独立して定義することである。

本書は設計・収集・測定計画であり、Production Swift実装、DB migration、CloudKit schema変更、Production CloudKit接続、物理端末データ変更、既存Rawログの変更、UI変更、MLX依存追加、学習、推論を承認しない。

現在の判断は次のとおりである。

- 匿名account scope 1、登録車両1台、終了済み8 session、2記録日、37.0 km、Raw 60,505件、観測PID 35である。
- 現snapshot revision 2による再decodeでは全件が有限かつ宣言範囲内であるが、取得時PID definition revisionではない。
- 取得時revision、走行状態coverage、縦断安定性、独立したsession/time splitが未成立である。
- 現データの学習入力とPrompt CのMLX feasibility spike実装は引き続き **`no-go`** である。計画作成、fixture成功、metadata実装だけで解除しない。

根拠表記は次を使う。

| 区分 | 意味 |
| --- | --- |
| `requirementDerived` | 要件から直接導かれる不変契約 |
| `currentImplementation` | 2026-07-28のcheckoutで確認した実装上の事実 |
| `realDataObserved` | 匿名実車監査で確認した記述的事実 |
| `candidate` | 後続phaseで比較・承認する案。Production確定ではない |
| `blocked` | 現在の証拠では決定、分類、または実行できない |

## 2. 現実装から導く設計境界

| 現在の事実 | 設計への含意 | 区分 |
| --- | --- | --- |
| `OBDPIDPollingPolicy`は高優先4 PIDを毎tick、その他を8 tickごとに選ぶ | policy versionとtickごとの選択集合がなければcadence差と欠測を分離できない | `currentImplementation` |
| `ReadMajorOBDPIDsUseCase`は応答辞書に存在するPIDだけをRaw通知する | 現Rawだけから要求分母、非応答、timeoutを復元できない | `currentImplementation` |
| `OBDPIDTelemetryPort`は応答辞書または一括errorを返す | PID別結果を保存する前に、Data adapterが観測できる結果を構造化する契約が必要である | `currentImplementation` |
| Rawは`ConnectionSessionLifecycleModel`を経由してGRDBへ追記される | metadataと要求結果もdevice callbackからApplication orchestrationを経てDomain repositoryへ渡す | `currentImplementation` |
| Rawの主キーは`(sessionID, sequence)`で、明示batch IDがない | batch、request outcome、Raw payloadは別の永続化表現にし、Raw行を上書きしない | `currentImplementation` |
| Analysisは現在のPID定義一覧を読み、Rawへ後適用する | 取得時definition snapshotを別に読み、明示的な互換判定後だけ学習候補へ進める | `currentImplementation` |
| capability表は応答確認済みPIDと収集選択を車両別に保持する | 「表にない」をunsupportedと推測せず、取得開始時の明示snapshotを固定する | `currentImplementation` |
| current Raw transfer payloadはRaw entryだけを運ぶ | 遠隔再現にはmanifest/request evidenceの転送versionを別途設計する必要がある | `currentImplementation` |

依存方向は `Platform -> Application -> Domain <- Data` とし、Appが構築する。View、iOS/macOS layout、ML runtimeは本計画の保存経路に参加しない。Raw payloadは再解析の独立証拠として現在の表現を維持し、metadata、取得時分類、派生値の都合で書き換えない。

## 3. 取得時metadata manifest

### 3.1 論理構造

最小の論理構造候補を次の3階層に分ける。

1. `ConnectionSessionAcquisitionManifest`: 1 sessionの生成環境、policy、ordered PID universe、取得時間境界を固定する。
2. `AcquisitionPIDDefinitionSnapshot`: manifest内の各PIDについて、取得時の意味とdecode契約を固定する。
3. `AcquisitionBatchEvidence`: 各poll cycleの選択集合と要求結果を固定し、応答payloadは既存Rawへ参照で結ぶ。

session manifestとPID snapshotは取得開始前、またはcapability確定後かつ最初のRaw要求前に原子的に確定する。確定後のin-place更新は禁止し、取得開始できない場合はRawを1件も保存せず明示失敗とする候補を優先する。Raw開始・終了時刻だけは取得の進行に伴う終端情報なので、manifest本体を変更せず、同じsessionに属するappend-only boundary eventまたは終端summaryとして記録する。

`modelInputManifestVersion`は「この取得が将来どの入力契約で解釈可能か」を表すschema versionであり、model ID、score、feature採用集合を意味しない。取得manifest自体をmodel featureへ混入させない。

### 3.2 metadataの意味、粒度、保存責務

| metadata | 保存する理由 | Domain上の意味 | 保存責務候補 | 粒度 |
| --- | --- | --- | --- | --- |
| app version | 生成code世代差を説明する | marketing versionとbuild versionからなる取得runtime identity | Appが値を注入し、Application/Loggingがsnapshotを作る | session |
| schema version | 保存形式とreader互換性を判定する | 製品が管理する安定schema contract version。SQLite `schema_version`単独ではない | Dataがversionを提供しApplicationがmanifestへ固定 | session |
| polling policy version | ordered要求集合とcadence規則の世代差を分離する | human-reviewed policy identity | Domain policyが定数を所有しApplicationが固定 | session |
| ordered requested PID set | 入力順、要求分母、policy選択母集団を再現する | 取得対象として有効な順序付き`Service/PID`集合 | Applicationがdefinition/capability/collection selection確定後に作成 | session |
| PID capability snapshot | supported、unsupported、未確認、collection enabledを区別する | 取得開始時点に確認済みの能力・選択事実 | Applicationがcapability repository結果と今回探索結果から作成 | session内PID |
| Service/PID | 定義と要求・Rawを安定結合する | OBD要求identity | Domain value object | PIDおよびrequest |
| PID definition revision | 取得時decode世代を固定する | 同一Service/PID定義の単調増加revision | PID definition repository読取結果からApplicationがsnapshot | PID |
| required byte count | payload適合性を再現する | 数式評価に必要な最小byte数 | PID definition snapshot | PID |
| formula version / definition identity | 同じrevision番号だけに依存せず式意味を固定する | versioned formula identityと、必要なら制限付き式のcanonical表現 | Domain snapshot。生成規則はhuman review対象 | PID |
| unit | feature尺度互換性を判定する | decode結果の意味単位 | PID definition snapshot | PID |
| validity range | invalid valueを取得時契約で判定する | `nil/nil`または両端を持つ許容範囲 | PID definition snapshot | PID |
| acquisition platform | platform cohort差を測る | `iPhone` / `iPad` / `macOS`だけの取得環境分類 | Appが注入しApplicationが固定 | session |
| Raw取得開始・終了時刻 | 接続時間と実取得時間を分離する | 最初のbatch開始と最後のbatch終端の実時間境界 | Application/Loggingがboundary eventを記録しDataが保存 | session summary |
| model input manifest version | 後続analysis input契約のreader互換性を判定する | 取得証拠からmodel input manifestへ変換するcontract version | Domainがversionを定義しApplicationが固定 | session |

`ordered requested PID set`は、取得開始時の全候補集合である。各batchで実際に要求した部分集合は§4のbatch evidenceへ保存する。capabilityは次を区別し、absenceから意味を推測しない。

- `supported`: capability応答または確認済み専用PID応答で明示された。
- `unsupported`: protocol上の明示的な非対応証拠が得られた場合だけ使用する。
- `indeterminate`: 未探索、応答曖昧、探索失敗、または現在のportでは分類不能である。
- `collectionEnabled`: supportedとは別軸の収集選択である。

### 3.3 immutable、互換性、legacyの扱い

| metadata | immutable範囲 | revision互換性判定 | 旧sessionに値がない場合 |
| --- | --- | --- | --- |
| app version | session確定後変更不可 | 同一version/buildは同一cohort候補。差があれば自動互換としない | `legacyAppVersionMissing` |
| schema version | session確定後変更不可 | readerが明示対応したversionだけ読める | `legacySchemaVersionMissing` |
| polling policy version | session確定後変更不可 | versionとordered setが一致する場合だけ同一policy候補 | `legacyPollingPolicyMissing` |
| ordered requested PID set | 順序を含め変更不可 | 順序、Service/PID、重複なしを完全一致で比較 | `legacyRequestedSetMissing` |
| PID capability snapshot | session取得開始時snapshotを変更不可 | PIDごとのstatus/selection/evidence versionを比較 | unsupportedへ補完せず`legacyCapabilityMissing` |
| Service/PID | manifest内identity変更不可 | byte完全一致 | Rawから観測PIDは分かっても要求集合は復元しない |
| PID definition revision | PID snapshot変更不可 | revisionだけでなくsemantic fieldsも比較 | `acquisitionRevisionUnavailable`のまま学習除外 |
| required byte count | PID snapshot変更不可 | exact match | 現定義から推測でbackfillしない |
| formula / definition identity | PID snapshot変更不可 | identity、canonicalization version、必要なら式をexact match | 承認済み再decode契約がなければincompatible |
| unit | PID snapshot変更不可 | normalized representationとsemantic unitをexact match | 現単位を取得時値と呼ばない |
| validity range | `nil`を含め変更不可 | lower/upperの有無と値をexact match | 取得時範囲不明として学習除外 |
| acquisition platform | session確定後変更不可 | platform cohortを分離して比較 | `unknownLegacyPlatform`。端末名で補完しない |
| Raw取得開始・終了時刻 | eventはappend-only、確定後変更不可 | timestamp format/versionと順序整合を検証 | Raw min/maxは参考再計算できるが保存値とは区別する |
| model input manifest version | session確定後変更不可 | readerが明示対応したversionだけ変換可能 | `legacyModelInputManifestVersionMissing` |

互換性判定候補は次の排他結果を返す。

- `exactlyCompatible`: manifest version、ordered set、全PID semantic identityが一致する。
- `approvedRedecodeCompatible`: 取得時revisionは固定済みで、別revisionによる再decodeを人間承認済みの変換契約が明示する。元manifestは変更しない。
- `incompatible`: identity、bytes、formula、unit、range、orderのいずれかが非互換である。
- `unknown`: legacy欠落、未知version、または証拠不足である。

`unknown`をcompatibleへ既定化しない。現在の8 sessionは取得時revisionがないため、記述的なsnapshot再分析には使えても、Prompt Cの学習入力には引き続き明示除外する。

### 3.4 privacy、同期、保持、migration、承認

| metadata | 個人情報・fingerprint risk | CloudKit同期候補 | retention候補 | migration | Production実装前の承認事項 |
| --- | --- | --- | --- | --- | --- |
| app version | 低。ただし希少buildとの組合せはfingerprintになり得る | 遠隔再解析に必要 | session metadataと同期間 | 新規保存先が必要 | version/build表現と匿名cohort粒度 |
| schema version | 低 | 必要 | session metadataと同期間 | 必要 | authorityとなるversion定義 |
| polling policy version | 低 | 必要 | Rawと同期間以上 | 必要 | version更新規則とrollback |
| ordered requested PID set | 中。車両能力との組合せでfingerprint化し得る | Raw再現に必要だがprivate scope限定 | Rawと同期間 | 必要 | 格納形式、容量benchmark、出力抑制 |
| PID capability snapshot | 中〜高。ECU/車両fingerprintになり得る | 必要性は高いが検索可能fieldにせずAsset/非queryable payload候補 | Rawと同期間 | 必要 | 最小列、非対応の証拠意味、CloudKit表現 |
| Service/PID | 単独は低、集合では中 | manifest/request evidenceに必要 | 親manifestと同期間 | 必要 | header等を追加しない範囲とidentity衝突 |
| PID definition revision | 低 | 必要 | Rawと同期間以上 | 必要 | revision運用とseed更新手順 |
| required byte count | 低 | 必要 | PID snapshotと同期間 | 必要 | exact互換規則 |
| formula / definition identity | 低〜中。式自体は個人情報でない | 遠隔再decodeに必要 | PID snapshotと同期間 | 必要 | canonicalization、式保存かidentity保存か |
| unit | 低 | 必要 | PID snapshotと同期間 | 必要 | unit normalization規則 |
| validity range | 低 | 必要 | PID snapshotと同期間 | 必要 | inclusive境界、`nil`意味 |
| acquisition platform | 低。端末名・installation IDを含めない | cohort再現に必要 | session metadataと同期間 | 現列の意味を再利用可能、manifest参照は追加必要 | enum versionとunknown処理 |
| Raw取得開始・終了時刻 | 中。個別走行時刻は行動fingerprint | 遠隔coverage再現には必要。外部出力では日/期間へ縮約 | session metadataと同期間 | 必要 | timestamp精度、CloudKit露出、匿名化 |
| model input manifest version | 低 | 必要 | manifestと同期間 | 必要 | version bump条件とreader matrix |

端末名、VIN、adapter identity、account ID、`VehicleID`原値はmodel featureへ入れない。保存上のowner結合にaccount/`VehicleID`が必要でも、manifestのsemantic内容・匿名成果物・model inputからは分離する。stable installation IDは本計画では追加候補にしない。platform差は`iPhone` / `iPad` / `macOS`だけで測る。

CloudKit同期は必要性と形式を分けて承認する。別端末でRawを再解析するにはmanifestとrequest evidenceも必要だが、どのrecord/Assetへ置くか、検索可能fieldにするか、payload format versionをどう上げるかはPhase 5まで未決定とする。local保存成功をCloudKit同期成功と扱わない。

retentionの原則は、Rawが再解析可能な間は対応manifestとrequest evidenceを失わないことである。local Raw cache削除時も、remote Rawが正式に保持されるならlocal session manifestの最小互換summaryを残す候補とする。session/account/vehicle削除時は既存の明示削除契約へ従い、孤立manifestだけを残さない。具体的期間と容量上限は実測前に固定しない。

## 4. 要求・非応答・batch metadata

### 4.1 推奨する最小候補

Raw payloadを独立保持したまま、次の3つを保存する候補を優先する。

```text
ConnectionSessionAcquisitionManifest
  └─ AcquisitionBatchEvidence (session内batch ordinal / batch ID)
       ├─ ordered selected PID indexes
       ├─ batch開始・終了、policy tick、batch-level failure
       └─ PIDRequestEvidence (要求したPIDごと)
            ├─ transportOutcome
            ├─ valueOutcome
            ├─ reason code / elapsed evidence
            └─ responded時だけ既存Raw sequenceへ参照
```

batch IDは端末横断の永続UUIDである必要はなく、`sessionID + batchOrdinal`の複合identity候補とする。匿名出力には原値を出さない。`ordered selected PID indexes`はsession manifestのordered PID setへのindexで表し、選択されなかったPIDはpolicyが評価を完了したbatchに限り`intentionalPollingOmission`として集合差から判定する。これにより、全省略PIDについて行を増やさずにintentional omissionを区別できる。

要求済みPIDは2軸で保持する。

| 軸 | 値候補 | 意味 |
| --- | --- | --- |
| selection | `requested` / `intentionalPollingOmission` | このpolicy tickで送信対象に選ばれたか |
| transport outcome | `responded` / `unsupported` / `timedOut` / `cancelled` / `transportFailure` / `unknownAfterTermination` | 通信境界で観測できた排他結果 |
| value outcome | `notEvaluated` / `decodedValid` / `decodeFailure` / `invalidValue` | 取得時definition snapshotでの排他評価 |

`responded`はRaw行が存在し、そのRaw sequenceを参照する。`decodeFailure`は応答payloadを取得時定義で評価できないこと、`invalidValue`は有限評価できても取得時validity range外であることを意味し、Raw payloadを削除・置換しない。missingは0へ置換せず、値配列とは別のmaskとして後段へ渡す。

`unsupported`は明示的なprotocol証拠がある場合だけ記録する。空応答をunsupportedへ変換しない。現在のportは一括dictionary/throwであるため、PID別`timedOut`、`cancelled`、`transportFailure`を安全に識別できない。Phase 4でData adapterの実際のcommand結果とtranscriptに基づく型付き結果を設計し、人間がstatus mappingを承認するまで個別理由を推測しない。

process終了等でbatch終端を永続化できなかった場合、未確定要求を`cancelled`へ補正しない。append-onlyのbatch開始証拠が残る場合は`unknownAfterTermination`、何もdurableでない場合はsession end reasonと欠落batch証拠として扱う。

### 4.2 保存方式候補の比較

| 候補 | 方式 | Raw独立性 | query性 | 取得性能・容量への影響 | 判断 |
| --- | --- | --- | --- | --- | --- |
| A | Raw行へbatch/result/definition列を追加 | 低い。Raw責務が広がる | 高い | 行ごとmetadata重複が増える。影響未測定 | 非推奨 |
| B | session manifest、batch表、request evidence表、既存Raw FK | 高い | 高い | batch/request書込が増える。transaction batchingで軽減候補だが未測定 | 推奨候補 |
| C | batchごとのversioned binary/JSON blobと既存Raw | 高い | 低〜中 | row数は減り得るがencode、全blob読込、migrationが増える。未測定 | 容量比較候補 |
| D | session manifestとpolicyから結果を全推定 | 高い | 見かけ上高い | 保存量は小さいがtimeout等を復元できない | 不採用 |

方式BをProduction採用と確定しない。synthetic負荷試験と実端末測定で、1 batch当たり要求数、write transaction回数、DB/WAL増分、取得loop時間、失敗時atomicity、CloudKit payload増分をA/B/Cで比較してから選ぶ。未測定のbyte数、latency、battery影響を断定しない。

batch、request evidence、Rawの永続化順は、1 batchを同一transactionで整合させる案と、取得を阻害しないappend queue案を比較する。いずれもRaw loggingをanalysisより優先し、metadata保存失敗を「成功したRaw取得」と黙って扱わない。backpressure、再試行、部分batchの意味をPhase 4で明示する。

## 5. 追加実車ログ収集計画

### 5.1 collection batchの定義

本節の`collection batch`は、OBDの要求batchではなく、前回匿名測定後に自然な利用で追加された終了済みsession集合である。必要日数、距離、session数を事前固定しない。現在の8 sessionを`B0`の記述的基準とし、以後`B1`、`B2`のような成果物内だけのordinalで比較する。原session IDや正確な個別時刻は出力しない。

各collection batchは次の両方で測る。

- incremental: 今回新たに追加されたsessionだけ。新規条件が増えたかを見る。
- cumulative: B0から今回まで。分布とsplit成立性が安定へ向かうかを見る。

batchの終了は固定距離でなく、通常利用で新しい記録日、session長、時間帯、状態候補、app/policy/platform cohortのいずれかが増えた時点を候補とし、人間が再測定単位を承認する。収集のために危険運転、意図的な高負荷、交通法規違反、不要な長時間idleを要求しない。high-loadは通常の安全運転で自然に実在した候補だけを測る。

### 5.2 batchごとの収集軸

| 軸 | incrementalで記録 | cumulativeで比較 | 注意 |
| --- | --- | --- | --- |
| 追加記録日 | Rawがあるdistinct UTC日数 | 記録日の増分と期間幅 | 個別走行時刻は出さない |
| 追加距離 | 成立sessionの距離合計と不成立理由 | 合計距離と成立率 | 距離source未保存のlegacyは限界を明示 |
| 終了済みsession | end reason、review decision別件数 | 独立session数 | activeは品質分母から除外 |
| 短/長session | Raw時間・sample数の分位帯別件数 | 各帯のwindow成立率 | 固定秒数で先に除外しない |
| 異なる走行時間帯 | local処理内の粗いversioned bucket件数 | bucket間coverage | timezone、bucket境界は別承認。正確な時刻を出さない |
| idle / low-speed / cruise | 候補gridごとのwindow、時間、session、日、距離 | support再現性 | 閾値をProduction確定しない |
| acceleration / deceleration | slope候補ごとの同じcoverage軸 | 符号・持続候補の再現性 | 急操作を依頼しない |
| warm-up / warmed | 確認済み温度/runtime候補のcoverage | 開始時点とplateau候補の再現性 | cold-startを時刻だけで推測しない |
| high-load候補 | 通常走行中に自然発生した候補coverage | session/日への分散 | 意図的な高負荷取得は禁止 |
| PID coverage | PID別session/日/window coverage | ordered setの再現性 | 要求分母がないlegacyは観測coverageと呼ぶ |
| cadence | PID別interval分布 | cohort内・batch間の分布差 | policy cohortを混ぜない |
| gap候補 | 固定/相対候補別件数とwindow影響 | gap mask分布 | timeoutと呼ばない |
| app version差 | version/build cohort別の全品質metric | cohort間差 | metadata実装後だけ正確に分類可能 |
| polling policy差 | policy/ordered set cohort別metric | 同一policy内安定性とpolicy間差 | legacyはunknown cohort |
| acquisition platform差 | iPhone/iPad/macOS別metric | platformごとのsupport | 端末名やIDは使わない |
| 整備前後period | 実在し人間確認済み境界の前後を分離 | 混入なしの記述比較 | 整備効果・因果を推測しない |

狙った状態を作る走行指示はしない。収集後に「自然に含まれていたか」を匿名測定し、不足状態は`insufficientCoverage`として残す。必要量は、複数collection batchでcoverage、分布、split可能性が安定するかを見てから提案する。

## 6. 各collection batch後の再測定契約

### 6.1 毎回同じ手順で測る項目

各batch後は、[`VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md`](VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md)の原本/snapshot/working copy、`mode=ro`、privacy、deterministic JSON契約を再利用する。新旧schema adapterと計算versionは出力へ明示し、同じversionの結果だけを直接比較する。

| 測定項目 | 最小出力 | 判定上の扱い |
| --- | --- | --- |
| window候補ごとの成立数 | window長/overlap/alignment候補別の成立・不成立件数と理由 | 候補を採用しない |
| PID別valid observation count | Service/PID、window/session/day別の有限範囲内件数 | requested分母と分離 |
| missing mask分布 | mask cardinality、PID別missing率、匿名集約pattern頻度 | 0補完しない。rare pattern出力はprivacy承認対象 |
| gap mask分布 | 候補別mask cardinality、最大gap、影響window数 | timeoutと読み替えない |
| session長別coverage | Raw時間/sample数quantile帯ごとのwindow成立率 | 特定長sessionの支配を検出 |
| 状態候補別coverage | window、時間、session、日、距離の5軸 | いずれかを他の代用にしない |
| split成立性 | train/validation/testへ割当可能な独立session数、日数、時間範囲、各状態support | Raw行random splitを禁止 |
| PID coverage再現性 | incremental/cumulative、cohort別session/day/window coverage | manifest一致cohort内で比較 |
| cadence安定性 | PID/cohort別interval median、IQR、分位点 | batchを跨ぐintervalを作らない |
| gap安定性 | 候補別件数率、window不成立率、分布 | policy/version差を分離 |

missing maskのpattern histogramは内部計算できるが、35 PIDの稀な組合せは車両fingerprintになり得る。外向けJSONは、PID別率、mask cardinality分布、privacy上承認された最小supportを満たす集約patternだけを出し、それ未満は決定的な`otherSuppressed`へまとめる候補とする。support値はprivacy review前に固定しない。

状態候補はFeature Spec §6の候補gridをversioned入力として使い、閾値ごとに別結果を出す。PIDが存在するだけで状態成立としない。`unclassified`と理由を保持する。

### 6.2 split成立性

split候補はsessionを最小groupとし、時間順のtrain→validation→testを崩さない。同一session、同一走行、重複window、同じsource intervalを複数splitへ入れない。整備periodが実在する場合は境界を跨いでreferenceへ混ぜない。

各候補splitについて、IDを出さずに次を報告する。

- 各splitの独立session数、記録日数、Raw観測時間幅、距離成立分の距離。
- 各splitのPID、状態、window、missing/gap support。
- validation/testがtrainより後の時間範囲にあるか。
- 特定1 sessionがwindow、状態、距離の大半を占めるか。
- split不能理由: `insufficientIndependentSessions`、`insufficientTimeSeparation`、`stateCoverageMissing`、`manifestCohortMismatch`、`maintenanceBoundaryUnknown`等。

現在の8 session・2記録日を形式的に3分割しても十分な独立評価を証明しない。十分性の閾値は複数batchの測定後まで確定しない。

### 6.3 前batchとの差と安定判定候補

採用方式・数値閾値は本書で固定しない。同一calculation version、同一manifest cohort、同じ候補定義について、次を並列に比較する。

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

## 7. offline集計器拡張案

### 7.1 拡張の要否

**拡張は必要であるが、本依頼では実装しない。** 現集計器はsession/PID/cadence/gap/decodeの匿名記述集計には使えるが、window候補、missing/gap mask、状態候補、split成立性、collection batch差、将来のmanifest/request evidenceを集計しない。現在の匿名監査結果を上書きせず、contract versionを上げた別結果として追加する。

### 7.2 追加する匿名集計項目

- collection batch ordinal、incremental/cumulative区分、app/schema/policy/platformの匿名cohort。
- manifest completenessと互換性結果の件数。manifest identity/digest原値は出さない。
- requested、responded、unsupported、timed out、cancelled、transport failure、decode failure、invalid value、intentional omissionの匿名件数と率。旧sessionは`requestEvidenceUnavailable`へ分離する。
- window候補別の成立/不成立理由、PID別valid observation count、missing/gap maskの安全な集約分布。
- session長quantile帯、状態候補別のwindow/時間/session/日/距離coverage。
- session/time split候補の成立性と匿名reason。
- 前batchとのmedian/IQR、分位点、分布距離、bootstrap CI候補。採用判定は出力しない。

### 7.3 privacy、read-only、決定性、不変性の契約

- VIN、account ID、`VehicleID`、session ID、端末名、adapter identity、Raw payload、payload hash、Manifest digest、個別走行時刻、個別時系列を出力しない。
- formula文字列、private scope manifest、取得manifestの内部digestも外向けJSONへ出さない。
- timestampは内部計算後に日数、期間幅、粗い承認済み時間帯bucketへ縮約する。
- session別・window別行は出力せず、分布と件数だけを出す。rare mask/cohortは決定的に抑制する。
- SQLiteはURI `mode=ro`、`query_only=ON`、`trusted_schema=OFF`、固定allowlistのparameterized SELECTだけを使う。
- 同じsnapshot、scope manifest、collection batch manifest、計算設定、tool versionからbyte-for-byte同じcanonical JSONを生成する。
- 実行前後にsnapshotとworking copyのfile set、SHA-256、size、mtimeが一致しなければ結果を破棄する。
- 同一入力で2回生成したJSONのSHA-256が一致し、privacy validatorが合格しなければ文書へ転記しない。

### 7.4 変更候補ファイル、単一責務、テスト

| ファイル候補 | 単一責務 | 変更/テスト候補 |
| --- | --- | --- |
| `Tools/VehicleChangeDataQuality/data_quality.py` | versioned schemaから匿名基礎集計用のread-only事実を作る | legacy/current/new schema adapter、request evidence completeness |
| `Tools/VehicleChangeDataQuality/collection_measurement.py`（新規） | Raw時系列からwindow/mask/state/split候補の匿名集計を作る | session境界、0補完禁止、候補grid、状態unclassified、split leakage防止 |
| `Tools/VehicleChangeDataQuality/collection_comparison.py`（新規） | 2つの互換匿名報告からbatch間差とCI候補を作る | 順序非依存、version拒否、cluster bootstrap seed固定 |
| `Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py` | CLI入力を検証し各責務を呼び出す | optional previous report/batch manifest、失敗時にpartial acceptedを出さない |
| `Tools/VehicleChangeDataQuality/privacy_validation.py` | 拡張JSONの禁止情報とrare出力契約を検証する | formula/digest/時刻/mask canary、identifier-shaped value |
| `Tools/VehicleChangeDataQuality/README.md` | 実行契約と証拠限界を利用者へ示す | 新command、schema/version、no-go境界 |
| `Tools/VehicleChangeDataQuality/Tests/test_data_quality.py` | schema/read-only/匿名基礎集計をsynthetic fixtureで検証する | legacy欠落、request outcome全分類、hash/size/mtime/file set |
| `Tools/VehicleChangeDataQuality/Tests/test_collection_measurement.py`（新規） | window/mask/state/split計算をsynthetic fixtureで検証する | 短/長session、gap、missing、状態候補、整備period分離 |
| `Tools/VehicleChangeDataQuality/Tests/test_collection_comparison.py`（新規） | batch比較とbootstrap決定性を検証する | 同一seed一致、cohort不一致拒否、候補順位反転 |

新規fileは既に承認済みの`Tools/VehicleChangeDataQuality/`と`Tests/`内にだけ置き、Production Swift、Xcode target、GRDB package、CloudKit、MLXへ依存させない。新directoryは作らない。

synthetic fixtureはtestごとのOS一時directoryにだけ生成し、全結果区分、missing/gap mask、複数session/day、短/長session、複数policy/app/platform cohort、整備period、legacy manifest欠落を含める。fixture成功は実車量、実車状態coverage、Production性能、CloudKit動作を証明しない。

### 7.5 実装後の実行コマンド候補

```sh
PYTHONPATH=Tools/VehicleChangeDataQuality \
  python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v

python3 Tools/VehicleChangeDataQuality/vehicle_change_data_quality.py \
  --database "$PROJECTZD8_WORK_DB" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json" \
  --collection-manifest "$PROJECTZD8_CAPTURE_ROOT/private/collection-batch.json" \
  --output "$PROJECTZD8_CAPTURE_ROOT/anonymous-collection-quality.json"

python3 Tools/VehicleChangeDataQuality/validate_anonymous_output.py \
  --report "$PROJECTZD8_CAPTURE_ROOT/anonymous-collection-quality.json" \
  --scope-manifest "$PROJECTZD8_CAPTURE_ROOT/private/scope-manifest.json"
```

既存snapshotを再分析する場合は、変更前に人間へ対象snapshot、collection batch範囲、出力予定の匿名項目、保持場所を提示し、明示承認を得る。実行前後にsnapshot/working copy双方のhash、size、mtime、file setを比較し、同一入力を2回実行して同一JSONを確認し、privacy validatorでVIN、`VehicleID`、session/account ID、端末名、Raw payload、Manifest digest、個別走行時刻が0件であることを確認する。本依頼では既存snapshotを再分析していない。

## 8. Production変更を分離するphase

各phaseは前phaseの成果物を入力とするが、承認と受入は独立させる。候補pathは現行配置に基づき、実装時にはtarget fileと直接依存を再確認する。

### Phase 1: Domain manifest契約

- 変更候補: `ProjectZD8/Domain/Entities/ConnectionSessionAcquisitionManifest.swift`、`AcquisitionRawBoundaryEvidence.swift`、`AcquisitionPIDDefinitionSnapshot.swift`、`ProjectZD8/Domain/Policies/AcquisitionManifestCompatibilityPolicy.swift`、manifestとRaw境界のrepository contractおよびmirror tests。
- 依存方向: framework非依存Domainだけ。Application/Data/Platform/GRDBをimportしない。
- 受入条件: 全metadataのvalue semantics、immutable範囲、exact/approvedRedecode/incompatible/unknown、legacy reasonに加え、manifest本体と開始・終了のappend-only Raw境界が分離してunit testで成立する。
- 未確認: formula identity方式、schema/policy/model-input version authority、headerをidentityへ含める必要性。
- 人間承認: Domain命名、canonicalization、compatibility matrix、legacy除外規則。

### Phase 2: Applicationの取得snapshot作成責務

- 実装範囲: `ProjectZD8/Application/Features/Logging/UseCases/CreateConnectionSessionAcquisitionManifestUseCase.swift`、`Application/Features/Logging/Ports/ConnectionSessionAcquisitionEvidencePort.swift`とmirror tests。`LiveTelemetryModel`、App composition、Data adapterは未接続のまま維持する。
- 依存方向: Loggingが明示入力とnarrow runtime-evidence portからDomain snapshotを作り、Domain repository contractへ保存する。ApplicationはData具体型を知らない。
- 受入条件: capability/definition/policy確定後かつ最初の要求前にmanifestが1回だけ保存され、append-only開始境界も保存された場合だけRaw開始許可を返し、失敗・cancel・再接続generationを混ぜない。
- version authority: app marketing/build、schema contract、platformはport、manifest、polling policy、model-input、formula canonicalizationは明示inputから供給し、Production値をハードコードしない。
- 未確認: production port/repository実装、manifestと開始境界のData transaction、session start/bind vehicleとの統合、終了境界のApplication wiring。
- 人間承認: cross-feature outcome ownerをLoggingとすること、snapshot時点、失敗時UXは別UI phaseへ送ること。

### Phase 3: Data/GRDB保存とmigration

- 変更候補: `ProjectZD8/Data/Persistence/GRDB/Database/ProjectZD8DatabaseMigrator.swift`、新しいmanifest/PID snapshot Record、`GRDBConnectionSessionAcquisitionManifestRepository.swift`、repository/migrator tests。
- 依存方向: DataがDomain repositoryを実装し、Application/Platformへ逆依存しない。
- 受入条件: 新規DB、現行release baseline DB、旧TestFlight相当fixtureを非破壊移行し、既存session/Raw count/digestを保持し、foreign key/integrity/readbackが合格する。実DB migration実行は別承認。
- 未確認: table分割、migration identifier、既存release baselineとの互換、index/容量。
- 人間承認: schema DDL、migration/rollback方針、fixtureが実インストールDB互換を代替しないこと。

### Phase 4: Raw/batch/request結果の永続化

- 変更候補: Domainの`AcquisitionBatchEvidence.swift`、`PIDRequestEvidence.swift`、repository contract、`Application/Features/LiveTelemetry/Ports/OBDPIDTelemetryPort.swift`、`ReadMajorOBDPIDsUseCase.swift`、Logging use case、Data OBD adapters、GRDB records/repositoryと全mirror tests。
- 依存方向: Data adapterが観測可能な通信結果をtyped Application portで返し、ApplicationがDomain evidenceへ変換し、Domain repositoryを通じてDataへ保存する。Raw payload表は独立維持する。
- 受入条件: 9要求区分を推測なしで区別し、respondedだけがRaw sequenceへ結合し、missingを0にせず、partial/cancel/terminationが整合し、取得性能・DB/WAL容量をfixtureと実端末で別測定する。
- 未確認: 実transportがPID別timeout/unsupportedをどこまで証明できるか、transaction/backpressure、B/C方式比較。
- 人間承認: transport transcriptに基づくstatus mapping、保存方式、性能budget、Raw優先失敗方針。

#### Phase 4F結果: 取得証拠保存のsynthetic性能・容量・rollback測定

2026-07-29に、既存Raw-only append経路をA、Phase 4E.1のbatch表＋request evidence表＋既存Raw FKをBとして、file-backed synthetic SQLiteだけで測定した。Aはresponded分のRawだけを保存し、Bはopen batch、request dispatch開始、respondedのRaw＋terminal原子保存、non-responded terminal、batch sealを保存するため、semantic evidence量と成功transaction数が異なる。以下の速度差を同一semantic処理の純粋overheadや方式Aの採用根拠として扱わない。

- 実行環境: Apple M3 Pro、19,327,352,832 byte memory、arm64、macOS 26.5.2 (25F84)、Xcode 26.6 (17F113)、GRDB 7.11.1、ProjectZD8 Debug test configuration、Swift language setting 5.0、macOS deployment target 26.4。
- SQLite条件: 各反復を独立したOS一時directoryのfile DBとし、`journal_mode=WAL`、`synchronous=NORMAL`、`foreign_keys=ON`を指定した。実インストールDB、snapshot、CloudKit、端末、adapter、車両は使用していない。
- matrix: A/B × batch数1/100 × 1/4/8/16要求 × 4 transport構成 × 4 value outcome × 8/256/4,096 byte payload = 768 workload。各workloadはwarm-up 1回を集計外とし、単発は5反復、100 batchは3反復した。p95は昇順nearest-rank、medianは偶数標本で中央2値の平均とした。Aはvalue outcomeを保存しないため、Aの4 value labelは同じRaw-only意味を独立fixtureで反復した値である。
- payloadは純粋なSQLite負荷軸である。8 byteを小、256 byteを中、4,096 byteを上限候補としたが、いずれも実車応答長、実PID、CAN header、ELM statusを表さない。
- 有効な最終測定commandは `xcodebuild test-without-building -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ProjectZD8Phase4F-DerivedData -enableCodeCoverage NO -only-testing:ProjectZD8Tests/GRDBAcquisitionEvidenceSyntheticMeasurementTests/testFullSyntheticMeasurementMatrixWhenRequested`。full matrix実行markerを `/tmp/ProjectZD8Phase4F/run-full-matrix` に置き、完了後に削除した。最終runは1,098.855秒で合格した。
- 機械可読結果: `/tmp/ProjectZD8Phase4F/phase4f-measurements.json`、2.2 MB。長い生logとfixture DBはrepositoryへ追加していない。最初のrunは全workload完走後、sandbox外 `/tmp` へのtest process直接書出しだけが拒否されたため結果を採用せず、測定定義を変えずsandbox内OS一時directoryへ出力してhostから指定pathへcopyした最終runだけを採用した。

100 batch、256 byte、`decodedValid`、responded 100%における要求数別の1 batch wall-clockは次のとおりである。単位はmsである。

| 要求数 | A median / p95 | B median / p95 | B/A median比 |
| ---: | ---: | ---: | ---: |
| 1 | 0.348 / 0.348 | 2.777 / 2.797 | 7.99 |
| 4 | 1.446 / 1.451 | 7.742 / 7.751 | 5.35 |
| 8 | 2.970 / 2.979 | 13.937 / 14.045 | 4.69 |
| 16 | 5.894 / 5.907 | 26.588 / 26.752 | 4.51 |

100 batch、16要求、256 byte、`decodedValid`のtransport構成別結果は次のとおりである。`min...max`も1 batch当たりms、`request median`は1 request当たりmsである。

| 構成 | 経路 | responded / non-responded | Raw / request行 | 成功transaction | batch median / p95 / min...max | request median | 概算総file増分 / batch |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| responded 100% | A | 1,600 / 0 | 1,600 / 0 | 1,600 | 5.894 / 5.907 / 5.862...5.907 | 0.368 | 37,153 byte |
| responded 100% | B | 1,600 / 0 | 1,600 / 1,600 | 3,400 | 26.588 / 26.752 / 26.577...26.752 | 1.662 | 45,978 byte |
| responded 75%＋timeout 25% | A | 1,200 / 400 | 1,200 / 0 | 1,200 | 4.480 / 4.491 / 4.445...4.491 | 0.280 | 7,126 byte |
| responded 75%＋timeout 25% | B | 1,200 / 400 | 1,200 / 1,600 | 3,400 | 24.760 / 25.165 / 24.651...25.165 | 1.547 | 44,711 byte |
| responded 50%＋mixed failure | A | 800 / 800 | 800 / 0 | 800 | 2.943 / 2.944 / 2.942...2.944 | 0.184 | 17,933 byte |
| responded 50%＋mixed failure | B | 800 / 800 | 800 / 1,600 | 3,400 | 22.619 / 22.623 / 22.557...22.623 | 1.414 | 8,669 byte |
| partial batch | A | 400 / 400 | 400 / 0 | 400 | 1.472 / 1.479 / 1.467...1.479 | 0.092 | 28,616 byte |
| partial batch | B | 400 / 400 | 400 / 1,600 | 1,800 | 12.825 / 12.894 / 12.819...12.894 | 0.802 | 40,204 byte |

partialの後半800要求は未dispatchの`selectedOnly`であり、non-responded欄は前半dispatch済みのうちRawを持たない400件だけを数える。Bは全1,600 request行を保持する。Aには要求証拠がないため、比較用のtransport件数はworkload入力の件数であり保存行ではない。

100 batch、16要求、responded 100%、`decodedValid`のpayload別medianでは、A/Bが8 byteで5.509/26.061 ms、256 byteで5.894/26.588 ms、4,096 byteで12.103/33.386 msだった。Bのp95はそれぞれ26.088、26.752、33.638 msである。256 byteのB value outcome別medianは`notEvaluated` 26.573、`decodedValid` 26.588、`decodeFailure` 26.589、`invalidValue` 26.702 msであり、このtest adapterではvalue enum自体による大きな時間差を観測しなかった。

responded 100%、100 batch、16要求、256 byteの各反復でfile sizeは決定的に同じだった。測定前はDB 4,096、WAL 284,312、SHM 32,768 byte。Aの測定後はDB 872,448、WAL 3,131,232、SHM 32,768 byteで、増分はDB 868,352、WAL 2,846,920、SHM 0 byte。Bの測定後はDB 1,425,408、WAL 3,460,832、SHM 32,768 byteで、増分はDB 1,421,312、WAL 3,176,520、SHM 0 byteだった。Bの総増分は100 batchで4,597,832 byte、Aより882,560 byte多い。別構成の1 batch概算値が単調でないのはWAL page確保とauto-checkpoint境界を含むためであり、retention容量へ線形外挿しない。

全768 workloadでforeign key check、integrity check、session Raw summaryとRaw実集計、0始まりRaw sequence連続性のfailureは0件だった。方式Bの100 batch validationでは800 request中600 respondedのcaseでbatch 100、request 800、Raw 600、canonical readback 100が一致した。respondedだけがRawを生成し、non-respondedと未dispatchはRawを生成しなかった。

retry専用testでは、responded exact retryを`.duplicate`、payload差のsemantic retryを`.conflict`として拒否し、前後のRaw/request/batch行、session Raw summary、DB/WAL/SHM size、既存semantic値が完全一致した。rollbackはProduction分岐を追加せずSQLite triggerでRaw insert失敗、request terminal update失敗、canonical Raw readback不一致、canonical request readback不一致、batch seal失敗の5 caseを各1回注入した。前4 caseはopen batch＋dispatch済みrequest、Raw 0、summary 0を保持し、seal失敗はterminal request＋Raw 1＋summary 1とopen batchを保持した。全caseで部分request更新、孤立Raw、部分summary、部分sealはなく、FK/integrityが合格し、trigger除去後に同一入力のresponded保存またはbatch sealを再試行して成功した。

legacy v8 synthetic fixture migration後の既存session／Raw不変性は既存migration testで引き続き確認する。このPhase 4F fixture成功を実インストールDB互換、実端末性能、battery、実adapter通信、実車取得、CloudKit、hosted CI、TestFlightの証拠へ拡張しない。

Phase 4G判定は二層に分ける。方式Bは最大測定軸でも100 batch平均のp95が33.638 ms/batchで、原子性、連続性、retry、整合性にsynthetic blockerを観測しなかったため、**別途人間が承認する限定的なProduction取得統合と実端末計測phaseへ進む技術的根拠はある**。一方、A比4.51〜11.45倍の時間差、WALを含む容量増分、未定義のpolling/backpressure/retention budgetがあるため、**方式BのProduction性能承認、常時有効化、実車受入、CloudKit同期へ進む根拠はまだない**。Phase 4GではRelease相当build、対象端末、batch cadence、queue/backpressure、battery、DB/WAL checkpoint、長時間容量を別測定し、人間が性能budgetとRaw優先失敗方針を承認するまで採用確定しない。

#### Phase 4G結果: 方式BのProduction取得経路への限定接続

2026-07-29に、Phase 4Fの人間承認を方式BのProductionソース配線とlocal integration検証だけへ適用した。UI、CloudKit、schema/migration、transport framing、PID/CAN/VIN、実機・実adapter・実車、background、TestFlight、Production環境は変更または実行していない。Phase 4Fの保存形式と測定実装も変更していないためfull matrixは再実行せず、通常synthetic testだけを再実行した。

- `ProjectZD8App`はHOME接続で親`ConnectionSession`を同期保存・車両関連付けした後、iOS/macOS compositionが同じ`GRDBConnectionSessionRepository`を`LiveTelemetryModel`、manifest、batch、終了回復へ注入する。`GRDBConnectionSessionRepository`は1個のProduction `DatabaseQueue`から取得repositoryを構築し、session、manifest、batch、request、Raw、取得境界の全操作で同じQueueを共有する。
- capability discoveryは既存の接続前workflowとして分離し、収集対象definition、capability、collection selection、polling順、generation、明示versionを確定してからmanifestとstarted boundaryを1 transactionで保存する。保存成功で返るpermissionがない限り、最初の収集batchのphysical requestはdispatchしない。manifest保存失敗または親session不在ではphysical requestは0件である。
- `LiveTelemetryModel`がgeneration内のpolling tickとbatch ordinalを0から1対1で単調採番する。各tickの選択subsetはmanifest内Service/PIDへ照合して元ordinalを保持し、request ordinalはbatch内の確定順とする。requestごとにdispatch開始を保存してからtyped observationを1回だけ取得し、respondedは同じ応答からRaw＋terminal evidenceを1 transactionで保存して表示sampleを生成する。timeout、cancelled、transport failure、unclassified、unsupportedにはRawを作らない。
- metadata、Raw、request、batchの保存失敗は取得成功へ変換せず、同一batchの後続physical requestを停止する。終了または世代交代は進行中taskの完了を待って旧generationを無効化し、その後のstale callbackによる新規証拠を拒否する。exact manifest retryはcanonical readback一致時だけpermissionを再利用し、完結済みbatchのexact retryは再送せずcanonical batchを返す。semantic差とdispatch後未確定状態は再送可能と推測しない。
- 正常切断、通信切断、取得失敗では、残存open batchを新しいtransport outcomeを発明せず`.failed/.persistenceFailure`へsealし、取得終了境界と親session終了を1 transactionで確定する。process termination回復ではdispatch済み未確定requestだけを`.unknownAfterTermination`、batchを`.terminatedUnknown/.processTerminated`へ変換し、取得終了境界と親sessionの`.unexpectedTermination`を同じtransactionで保存する。
- local integrationはfile-backed GRDBとtyped fake observationで、manifest gate、stable identity、決定的request順、responded-only Raw、Raw＋terminal原子性、non-responded Raw 0件、後続dispatch停止、stale generation拒否、retry非重複、batch集計整合、明示終了、rollback、simulated termination recoveryを確認した。macOS全unit testとiOS Simulator buildも別々に実行し、実デバイス・実車・hosted CI・TestFlight・Production CloudKitの証拠には拡張しない。
- 最終local gateはmacOS `ProjectZD8Tests` 384件中382件成功、2件skip、失敗0件だった。skipは明示opt-inが必要なPhase 4F full matrixを含む。iOS 26.5 SimulatorのUUID `185B4100-AA7B-4E46-AC5C-0CDAA1E77AB3`と専用DerivedData `/tmp/ProjectZD8Phase4G-iOS-DerivedData`を指定したbuildも成功した。

この結果は、別承認の実機性能測定計画を作成できるlocal前提が整ったことだけを示す。実機性能測定の実行、常時有効化、一般リリースへは進んでいない。次の人間判断には、対象端末・adapter・車両、Release相当条件、batch cadence、queue/backpressure、battery/thermal、DB/WAL checkpoint、長時間容量、性能budget、Raw優先失敗方針が残る。

#### Phase 4H設計ゲート: 方式Bの実機性能測定計画

2026-07-29時点の判定は **`No-Go`** である。この判定は方式BのProduction配線を否定するものではなく、要求された実機性能指標を同一runへ再現可能に結合する計測境界が現Productionに不足し、対象端末、adapter、transport、benchまたは車両、Release相当配布経路、性能budgetも人間未決定であるため、実Bluetooth、ExternalAccessory、USB、実adapter、実車への接続・送信を開始しないという実行前ゲートである。

##### 4H.1 現実装で確定した測定境界

- iOSとnative macOSは別測定cohortとする。両platformを製品対象にする場合は両方を測定し、片方の結果を他方へ転用しない。最初のcohort候補は、外部file観測とInstruments取得が容易なnative macOSの安全なbenchであるが、採用には人間承認が必要である。
- capability discoveryは`LiveTelemetryModel.poll`内でmanifest保存より前に完了する。collection性能の集計開始はmanifest保存開始とし、discovery時間は別区間として記録して混ぜない。
- manifestとstarted boundaryの保存成功後だけ`ConnectionSessionAcquisitionController`がpermissionを保持し、最初のcollection batchを許可する。manifest失敗または親session不在時のphysical requestは0件でなければならない。
- collection loopはtick 0を即時実行し、tick 1以降は**前batchの処理完了後**に250 ms sleepする。固定4 Hz scheduleではなく、batch処理時間とtask scheduling遅延が次の開始時刻へ加算される。高優先4要求は毎tick、その他は8 tickごとであるが、実要求数は取得時manifestと各batchの選択集合からだけ確定する。
- 方式Bは1 batchにつき、open batch保存1回、各requestのdispatch開始保存1回、各request terminal保存1回、batch seal 1回を行う。responded terminalはRawと同一transaction、non-responded terminalはRawなしである。これに加え、累積距離が変化した場合は同じsession repositoryによるsession保存が発生し得るため、Phase 4Fの純粋な方式B transaction数をProduction全write数とみなさない。
- session、manifest、batch、request、Raw、取得終了は1個の`GRDBConnectionSessionRepository`が保持する同じ`DatabaseQueue`を共有する。ただしPID定義、車両capability、整備などは同じ`projectzd8.sqlite`を別々に開く実装があり、file全体のwriter競合を「取得Queue内待機」だけへ帰属させない。
- Productionの`DatabaseQueue(path:)`はGRDB 7.11.1の既定configurationで開かれ、コード上はjournal mode、synchronous、auto-checkpoint、manual checkpoint、busy timeoutを明示しない。実DBのjournal modeは永続状態をruntimeで取得するまで不明である。Phase 4F fixtureだけがWAL、NORMAL、foreign keys ONを明示したため、そのWAL結果をProductionへ転用しない。
- appのscene phase変更はactive復帰時の履歴・整備refreshだけを行い、取得loopをbackground遷移で停止または継続する明示契約を持たない。background継続、suspension、ExternalAccessory/Bluetooth維持、終了時open状態は実機で別々に確認する必要がある。
- process termination recoveryは次回の認証account有効化時に走る。dispatch済み未確定requestを`unknownAfterTermination`、open batchを`terminatedUnknown/processTerminated`、sessionを`unexpectedTermination`へ同一transactionで閉じるが、実OS terminationからの回復は未検証である。

##### 4H.2 対象cohortと人間が固定する実行条件

各run前に次をJSONの`approved_conditions`へ固定する。未決定値をadapter名、protocol string、PID、payload、timeout、車両応答から推測しない。

| 軸 | 固定する値 | 現在の判定 |
| --- | --- | --- |
| platform | iOS実機またはnative macOS | 両者は別cohort。測定対象は人間未決定 |
| device | 製品名ではなく非固有のhardware model、OS build、memory tier | 人間未決定。serial number、端末名、UDIDは保存禁止 |
| build | Release相当configuration、marketing/build version、git commit、署名種別、直接install/TestFlight等の配布経路 | 人間未決定。Debug結果との混在禁止 |
| adapter | 人間が実物と資料で確認したmaker/model/firmware cohort | 人間未決定。個体serialは保存禁止 |
| transport | iOS BLE、iOS ExternalAccessory、macOS USB serial、macOS Bluetooth Classic、macOS BLEのうち確認済みの1経路 | 実装候補は存在するが実物契約は未確認。iOS ExternalAccessoryはBundle許可protocolをrepositoryから確認できない |
| environment | 安全なbench、または通常利用だけを行う承認済み実車 | 人間未決定。公道での意図的高負荷、危険操作、運転者による計測操作は禁止 |
| account/sync | 専用test account、automatic session uploadの状態、network条件、既存DB初期状態 | 人間未決定。CloudKit uploadを測定へ混入させないrunを先に行う |
| storage | 測定前のDB/sidecar size、空き容量、journal/synchronous/checkpoint PRAGMA実値 | runtime取得が必要。既存DBを変更せずread-onlyで記録する |
| workload | Production manifestのordered set、batchごとの実選択集合、typed observation、実payload長 | 実行時に確定。Phase 4Fの1/4/8/16要求と8/256/4,096 byteを実機値として再利用しない |

demo、fake、synthetic、実adapter bench、実車は`evidence_class`をそれぞれ別値にし、同じ統計へpoolしない。実adapter benchはtransportと保存性能の証拠にはなり得るが、実車response分布や車両安全性の証拠にはしない。

##### 4H.3 推奨matrixと反復契約

実行順は次の段階を飛ばさない。ある段階の停止条件発生時は後続へ進まない。

1. `release_install_sanity`: 承認済みRelease相当build、対象端末、対象adapter、対象transportが資料どおり特定でき、未確認commandなしで接続候補まで到達できることを確認する。physical requestはまだ送らない。
2. `bench_short`: 安全なbenchで通常Production loopを使い、tick 0と少なくとも1回の8 tick policy cycleを含む短時間runを行う。manifest gate、ordinal、request sequence、Raw対応、終了後open batch 0を先に検査する。
3. `bench_repeated`: 同じ初期条件から独立runを反復し、cold/warm startを別cohortにする。反復数はPhase 4Fの3回を最低候補にできるが、実機採用値ではなく人間が事前承認する。
4. `bench_endurance`: 想定する最大連続利用時間を覆う耐久runとする。時間、許容DB増分、最低空き容量、給電条件、battery下限は製品利用条件から人間が事前承認し、短時間runから線形外挿しない。
5. `lifecycle`: 通常終了、ユーザー切断、通信切断、cancel、foreground/background、承認済み方法によるprocess terminationと次回起動回復を別runで行う。OSによるsuspensionとtransport切断を同一原因として集計しない。
6. `vehicle_normal_use`: benchが全gateを通過した後だけ、承認済み車両で安全な通常利用を行う。benchと同じadapter/transport/buildから変える場合は新cohortとして短時間gateへ戻る。

warm-upは「最初の完全なpolicy cycle」を除外候補とし、除外前の値も保存する。短時間、反復、耐久の具体時間と回数は現証拠から確定できないため、人間承認欄を空のまま実行しない。外れ値は削除せず、OS更新、接続再確立、他process負荷など事前定義した外因がある場合だけ理由付きで`excluded_from_summary`とし、生値は保持する。medianは偶数標本の中央2値平均、p95は昇順nearest-rank、最大値は全採用標本の最大とする。batchを独立反復としてrun間差を過小評価せず、batch内統計とrun単位統計を両方出す。

##### 4H.4 指標、取得元、現時点の可否

| 指標 | 取得方法 | 既存instrumentationだけでの可否 |
| --- | --- | --- |
| request経過時間 | 保存済み`PIDRequestEvidence.elapsedNanoseconds`。dispatch開始保存後からtyped transport outcomeまでの単調時間 | 可。ただしQueue待機、terminal保存時間を含まない |
| batch wall-clock | batch `completedAt - startedAt`を集計 | 近似可。wall clockであり段階別内訳と単調性はない |
| manifest開始保存 | call直前からpermission返却までの単調時間 | 不可。開始・終了計測点がない |
| open batch metadata保存 | `beginBatch` call前、`DatabaseQueue.write` closure開始、call返却を分離 | 不可 |
| dispatchからtyped observation | request経過時間と同じ | 可 |
| responded Raw＋terminal保存 | repository call前後とtransaction内時刻 | 不可 |
| non-responded terminal保存 | repository call前後とtransaction内時刻 | 不可 |
| batch seal | `finishBatch` call前後とtransaction内時刻 | 不可 |
| 予定時刻からの遅延 | 前batch完了後250 msという現policyに対するtask wake時刻と実batch開始を単調時計で比較 | 不可。固定scheduleとして扱わない |
| Queue待機・backpressure | repository call、write closure開始、transaction終了を同一単調時計で分離し、同じDB fileの他Queue競合も記録 | 不可 |
| skipped/late/cancelled/stale | policy tickとbatch ordinalの期待列、cancel/stale拒否event、terminal evidenceを照合 | cancelledの一部だけ可。skipped/late/stale countは不可 |
| DB/sidecar増分 | run前、warm-up後、終了直前、graceful終了後、checkpoint後のfile byte数 | macOSは外部観測候補。iOSはcontainer取得権限と手順の人間承認が必要 |
| journal/checkpoint | read-only PRAGMA snapshotとcheckpoint event/所要時間。journalがWALでない場合はWAL指標を`not_applicable`にする | journal実値は取得可能な候補。checkpoint発生・所要時間は不可 |
| CPU/memory/energy | 対象Xcode版で人間承認したInstruments traceをrun IDに対応付け、process CPU、resident/peak memory、memory pressure、energyを取得 | 外部traceで候補。batch/requestへの厳密対応はsignpostなしでは不可 |
| battery/thermal | 端末の測定前後batteryと給電条件、OS thermal state遷移、Instruments energy evidenceを記録 | battery前後は手動候補。thermal遷移の機械可読結合は不可 |
| lifecycle/open状態 | scene phase、transport open/close、session/batch終了証拠、次回起動recoveryを時系列照合 | DB終端は一部可。scene/transport open時系列は不可 |

DB、WAL、SHMは存在を前提にせず、Production DB本体、`-wal`、`-shm`、rollback journalの実在とbyte数を別々に記録する。WAL時だけ`wal_autocheckpoint`、page size、checkpoint前後frame数と所要時間を対象にする。checkpointを発生させる操作はDB状態を変更し得るため、read-only PRAGMA確認と分離し、人間が方式、実行時点、`PASSIVE/FULL/RESTART/TRUNCATE`のいずれを許可するか承認するまで実行しない。

##### 4H.5 安全停止条件

次は数値budgetに依存しない即時停止条件である。

- adapter、transport、framing、timeout、許可protocol、接続対象を資料と実機表示から一致確認できない。
- 未確認PID、CAN、VIN、ELM command、protocol string、UUID、車両操作が必要になる。
- manifest/started gate前にphysical requestが1件でも発生する。
- responded Rawとterminal evidence、session終了と取得終了、termination recoveryのいずれかに部分成功がある。
- policy tick、batch ordinal、request ordinal、manifest PID ordinal、Raw sequenceに重複、欠落、逆行、不一致がある。
- 終了または回復後にopen batch、dispatch未確定request、未終了sessionが残る。
- 保存失敗後に同一batchの後続physical requestが発生する。
- queue待機またはstart-to-start間隔がrun中に増加し続ける兆候を示す。判定windowと許容傾向は人間が事前承認する。
- OSがserious/critical thermal stateまたはmemory pressureを報告する、batteryまたは空き容量が人間承認値を下回る、DB/sidecarが承認容量を超える。
- UI、CloudKit、background、upload、offline archiveに計画外の副作用が発生する。
- 計測のためにProductionのcadence、保存意味、Raw優先順位、payload、timeout、retry、終了意味を変える必要がある。

CPU、memory、battery、polling遅延、Queue待機、DB/sidecar容量の数値閾値は現在の証拠から決めない。人間は対象deviceの製品budget、想定最大session、最低空き容量、給電条件、許容thermal state、Raw優先失敗方針を測定前に固定する。

##### 4H.6 匿名機械可読証拠

Phase 4F JSONの`percentileMethod`、workload別`measurements`、`repetitions`、file別`before/after/delta`、整合性真偽値は再利用できる。実機artifactはPhase 4F schemaへ追記せず、`phase4h-real-device-performance-v1`として分離する。最小top-level構造は次とする。

```json
{
  "schema": "phase4h-real-device-performance-v1",
  "evidence_class": "real_adapter_bench_or_real_vehicle",
  "measurement_run_id": "random-run-id",
  "build": {
    "commit": "full-git-commit",
    "configuration": "human-approved-release-equivalent",
    "marketing_version": "from-bundle",
    "build_version": "from-bundle",
    "distribution": "human-approved-route"
  },
  "environment": {
    "platform": "ios-device-or-native-macos",
    "hardware_model": "non-unique-model",
    "os_build": "recorded-at-run",
    "adapter_model": "human-verified-model",
    "adapter_firmware_cohort": "human-approved-non-unique-value",
    "transport": "verified-production-transport",
    "environment_class": "safe-bench-or-normal-use",
    "power_condition": "recorded-condition"
  },
  "contracts": {
    "manifest_version": 1,
    "schema_contract_version": 1,
    "polling_policy_version": 1,
    "model_input_manifest_version": 1,
    "formula_canonicalization_version": 1
  },
  "approved_conditions": {},
  "workload_observed": {},
  "metrics": {
    "manifest": {},
    "batches": {},
    "requests": {},
    "queue_and_schedule": {},
    "database_files": {},
    "checkpoint": {},
    "process_resources": {},
    "battery_and_thermal": {},
    "lifecycle": {}
  },
  "integrity": {},
  "failures": [],
  "stop_reason": null,
  "commands": [],
  "artifacts": [],
  "sha256": "sha256-of-canonical-json-with-this-field-omitted"
}
```

repositoryへはschema説明と匿名集計だけを置く候補とし、長いlog、Instruments trace、sysdiagnose、DB copy、WAL/SHM、Raw payload、VIN、VehicleID、session/account ID、端末名、UDID、adapter serial、認証情報、個別走行時刻を追加しない。repository外artifact保存先、保持期間、アクセス権、削除責任者は人間承認事項である。実行commandはsecret、固有path、UDIDをplaceholderへ置換した再現用commandとし、元commandはrepository外の制限付き記録にだけ保持する。JSONはkey順を固定してSHA-256を計算し、各外部artifactも個別SHA-256とbyte数を記録する。

##### 4H.7 最小追加設計と解除条件

要求された全指標には既存instrumentationだけでは不足する。Production sourceをこのPhaseで変更せず、次の最小案を別承認へ送る。

1. schema、migration、cadence、transport、PID mapping、Raw保存意味、UI、CloudKitを変更しない。
2. no-opを既定とする型付きperformance event portをApplicationへ置き、manifest、batch、request、cancel/stale、lifecycleの開始・終了を単調時刻と匿名ordinalだけで通知する。
3. Data/GRDBは`databaseQueue.write`呼出直前、write closure開始、commit/returnの3点だけを通知し、queue待機近似とtransaction時間を分離する。SQL、payload、identifierは通知しない。
4. Release相当の明示測定buildだけで`os_signpost` adapterをApp compositionから注入する。常時有効化、新schema、DB保存、buffer、upload、UI、background処理、repository内exportは行わない。
5. thermal、battery、memory、DB file、PRAGMA、checkpointはProduction semantic eventへ混ぜず、承認済み外部計測と制限付きartifactからoffline joinする。run IDだけを共通鍵とする。
6. signpost schema、privacy、overheadのsynthetic/local testとRelease buildを先に検証し、instrumentation有無で取得結果、transaction数、Raw digest、cadence policyが不変であることを確認する。

この案は新しいProduction instrumentationとrepository外artifactを必要とするため、人間承認なしに実装しない。解除には、対象platform/device/build/distribution、adapter/transport/benchまたは車両、短時間・反復・耐久条件、各数値budget、checkpoint方針、process termination手順、artifact保存・保持・削除、instrumentationの配置と有効化方式、Raw優先失敗方針のすべてが必要である。承認後も最初の許可は`release_install_sanity`と`bench_short`までに限定し、実車、background耐久、常時有効化、一般リリース、CloudKitは別gateとする。

##### 4H.8 承認済みinstrumentation実装結果

2026-07-29に、人間は§4H.7の最小追加設計と`Data/Diagnostics`配置規則の更新を承認した。実装後も実機測定開始判定は **`No-Go`** のままであり、今回の承認を対象端末、adapter、transport、benchまたは車両、性能budget、checkpoint、artifact保持、実車送信への承認へ拡張しない。

- Applicationへ、個人、account、session、vehicle、device、adapter、PID、payloadを受け取らず、process内generation、batch/request ordinal、policy tick、schedule遅延だけを扱う`AcquisitionPerformanceEventPort`を追加した。通常buildの既定実装はno-opである。
- 取得開始、manifest、batch全体、open metadata、request dispatch、typed transport、responded Raw＋terminal、non-responded terminal、batch seal、stale拒否、世代cancel、session終了、termination recoveryを別操作として通知する。GRDB writeはcall直前のbegin、write closure冒頭のQueue entry、return後のendを同じ匿名intervalへ結び付ける。
- tick 0はschedule遅延を持たず、tick 1以降は前batch完了後の250 ms sleepについて、予定wakeから実wakeまでの非負超過だけを単調clockで通知する。polling cadenceと要求選択方針は変更していない。
- `Data/Diagnostics`の`OSSignpostAcquisitionPerformanceAdapter`は、`ACQUISITION_PERFORMANCE_MEASUREMENT` compile conditionがあるbuildで、環境変数`PROJECTZD8_ACQUISITION_PERFORMANCE_RUN_ID`が1〜64 byteの許可ASCIIだけを満たす場合に限ってcompositionから注入される。無効・欠落時と通常buildはno-opであり、DB、file、memory buffer、network、UIへ計測値を保存・送信しない。
- file-backed GRDB integration testでcontroller、transport、Queue entry、各write終了のevent到達順、stale拒否とcancelの分類を確認した。Production polling testではtick 0の`nil`と、固定clockによるtick 1の10 ms超過を確認した。signpost run ID privacy gateとno-op lifecycleもtestした。
- macOS Debug `build-for-testing`、関連4 test suite 23件、macOS unit target全390件（388件成功、2件skip、失敗0件）、macOS Release、iOS Simulator Releaseを実行し、いずれも成功した。2件のRelease buildでは`ACQUISITION_PERFORMANCE_MEASUREMENT`を明示し、条件付きcomposition branchをcompileした。既存のSwift 6 actor-isolation警告は残るが、今回の計測変更に起因するbuild errorはない。

この結果で、manifest、各batch/request、Queue entry、schedule遅延、stale/cancelをInstruments traceへ結合するlocal基盤は成立した。一方、CPU、memory、energy、battery、thermal、DB/sidecar byte、runtime PRAGMA、checkpoint、scene/transport lifecycleは外部artifactまたは追加の別承認範囲であり、実値は得ていない。instrumentation有無の実機overhead、実adapter通信、実車response、長時間容量、background、process termination、TestFlight、hosted CI、Production CloudKitも未検証である。

#### Phase 4I運用叩き台: Release install sanityと安全なbench short

この節は、未決定事項を測定後に後付けしないための最初の運用baselineである。初回runは次の既定値を変更せずに使い、実行結果から閾値を緩めない。現物またはruntimeからしか得られない値は方針未決定ではなく`run_record`として実行前に記録し、取得不能または候補不一致なら`release_install_sanity`を`No-Go`で終了する。初回結果を受けた変更は、元の値、変更理由、承認者、適用開始runを残した次revisionとして事前承認する。

##### 4I.1 初回cohortと承認baseline

| 軸 | 初回baseline | 実行時の確定方法または停止条件 |
| --- | --- | --- |
| platform | native macOS | iOS App on Macへ置換しない |
| hardware | Apple M3 Pro、19,327,352,832 byte memoryのPhase 4Fと同じ非固有cohort | `sysctl -n hw.model machdep.cpu.brand_string hw.memsize`で非固有値だけを`run_record`へ記録する。serial number、hardware UUIDを出力し得るcommandは実行しない。同一cohortでなければ新cohort承認まで停止 |
| OS | macOS 26.5.2、build 25F84 | `sw_vers`で一致確認する。OS更新後は新cohortとして停止 |
| build | scheme `ProjectZD8`、configuration `Release`、`ACQUISITION_PERFORMANCE_MEASUREMENT`を明示 | 通常Release buildと測定Release buildを別DerivedDataへ作る。通常buildがno-op、測定buildが有効run IDでだけsignpostを出すことを先に確認 |
| distribution | Xcode直接install | Archive、TestFlight、App Store、一般配布へ拡張しない。bundleのmarketing/build version、署名種別、hardened runtime有無、designated requirementのSHA-256だけをinstall後にread-only記録し、TeamIdentifierやcertificate識別値を匿名集計へ入れない |
| source snapshot | clean worktreeのfull Git commit | `git status --short`が空でなければ停止する。`git rev-parse HEAD`の40桁値を記録し、測定中にsourceまたはbuild settingsを変更しない |
| adapter candidate | OBD Solutions LLC `OBDLink EX` | 公式資料と実物表示のmaker/modelが完全一致した場合だけ採用する。serial numberは記録しない。異なるmodelを代用しない |
| firmware cohort | 実物に対する公式tool表示のmajor.minor version | versionだけを`run_record`へ記録する。確認にWindows等の別環境が必要ならsanity前に人間が確認し、確認不能なら停止。測定phaseでfirmware更新しない |
| transport | repositoryのnative macOS `.serial`経路、`MacOS115200BaudOBDSerialTransport` | USB接続後にmacOSが生成したserial候補とアプリ表示が同じ1件を指すことを確認する。device pathは制限付き外部原本だけに保持し、匿名集計へ入れない。Bluetoothへfallbackしない |
| bench | 実車配線を一切使用しない、規格適合OBD-II ECU simulator＋電流制限付き絶縁12 V安定化電源＋OBDLink EX＋USB接続Mac | simulatorのmaker/model、対応するlegislated OBD-II mode、電圧・電流制限を資料と実物で確認する。任意CAN送信、VIN、manufacturer固有mode、車両harnessが必要なら停止 |
| power | Macは純正または承認済みAC給電あり、benchは12.0 V安定化給電あり | 開始前battery 80%以上。bench電源はadapter公式8〜30 V範囲内でも初回は12.0 V固定。電源変更を性能調整に使わない |
| network | Wi-Fi、Ethernet、VPNを切断したoffline | trace開始前にnetwork path不在を確認する。認証復元等にnetworkが必要ならtrace外で完了し、再度offlineを確認できなければ停止 |
| account/sync | 専用test account、`automaticSessionUploadEnabled = false`、manual uploadなし | 設定をtrace前に確認し、起動後CloudKit/upload eventまたは同期UI操作が発生したら停止 |
| DB initial state | 同じschemaへmigration済みの専用local test DB、open session 0、open batch 0、dispatch未確定request 0 | Production利用DB、TestFlight DB、復元DBを使わない。実行前read-only queryで件数を記録し、不整合があれば削除・修復せず停止 |
| run | 1回、tick 0からtick 8のterminal完了まで、wall-clock上限60秒 | tick 8が60秒以内にterminalにならなければtimeoutとして停止。余分なcycleを意図的に継続しない |
| anonymous run ID | `p4i_macos_usb_bench_short_001` | 同じIDを再利用しない。再試行は末尾を`002`へ進め、失敗artifactも保持する |

[OBDLink EX公式製品情報](https://www.obdlink.com/products/obdlink-ex/)はUSB 2.0接続と8〜30 Vの動作範囲を示す一方、対応platform欄はAndroidとWindowsであり、macOSを公式対応とみなさない。したがって、このbaselineはrepositoryに存在するmacOS USB serial実装を安全なbenchで検証する候補であり、公式macOS互換性の主張ではない。firmware cohortの確認方法は[公式firmware更新案内](https://support.obdlink.com/support/solutions/articles/43000705180-update-obdlink-adapter-firmware)に限定し、非公式toolの表示を採用しない。

##### 4I.2 初回停止budget

| 指標 | 初回budget | 判定方法 |
| --- | ---: | --- |
| Queue待機 | 各write 100 ms以下 | signpost beginから`DatabaseQueueEntry`まで。1件でも超過なら停止 |
| schedule遅延 | tick 1以降各100 ms以下 | `scheduleDelayNanoseconds`。欠落、負値相当、超過を許容しない |
| DB/sidecar増分 | DB、`-wal`、`-shm`、rollback journalの実在file合計16 MiB以下 | run直前とgraceful終了後をfile別に測定。途中checkpointなし。縮小を成功条件にしない |
| CPU | ProjectZD8 processの平均25%以下、最大100%以下 | Instrumentsの同一run区間。system全体CPUと混ぜない |
| memory | peak resident 512 MiB以下、開始後増分64 MiB以下 | Instrumentsのresident/peak。終了時減少を理由に途中peakを除外しない |
| energy | Instrumentsで`High`相当が連続5秒未満 | tool version固有のscoreは原値も保持し、分類だけで他cohortと比較しない |
| battery | 開始80%以上、給電中、run中低下1 percentage point以下 | 開始前後の表示値。短時間で粒度未満なら0として記録 |
| thermal | run全体で`nominal`のみ | `fair`、`serious`、`critical`へ遷移したら即時停止 |
| free storage | 開始時10 GiB以上 | repositoryとartifact volumeを別々に確認し、どちらかが不足なら停止 |
| stale/cancel | stale 0、計画外cancel 0 | graceful終了の計画済みgeneration cancelは別分類 |

Phase 4Fのsynthetic値はこのbudgetの合格証拠ではない。初回budgetは短時間sanityで明白なbackpressure、容量暴走、resource異常を止める保守的な値であり、製品SLA、長時間容量、iOS budgetへ転用しない。

##### 4I.3 repository外artifact契約

- 保存先は実行ユーザーだけが読める`~/Library/Application Support/ProjectZD8MeasurementArtifacts/Phase4I/<anonymous-run-id>/`とする。作成後にowner以外のread/write権限がないことを確認し、repository、iCloud Drive、共有folderへ移動しない。
- 保持期間は作成日から30日、削除ownerは測定実行者とする。人間reviewが継続中なら、期限前に新しい削除日と承認者を外部manifestへ追記する。
- 保持対象はRelease build/install manifest、codesign検査、sanitized command log、signpost/Instruments trace、resource summary、read-only PRAGMA結果、DB/sidecarのfile名別byte数、匿名集計JSONである。DB copy、WAL/SHM copy、Raw payload、sysdiagnose、端末名、serial、UDID、account/session/VehicleID、VIN、device pathは匿名artifactへ含めない。
- 各artifactは作成直後にSHA-256とbyte数を外部manifestへ記録する。集計JSONの`sha256`はそのfieldを除いたkey順固定JSONから計算する。原本から匿名集計を生成した後も原本hashを変更しない。

##### 4I.4 実行順序

1. `static_and_local_gate`: clean commitを確認し、macOS Debug `build-for-testing`、Phase 4H関連test、macOS unit target全体、通常macOS Release、計測条件付きmacOS Release、`git diff --check`を順に実行する。いずれか失敗時はinstallしない。
2. `release_install_sanity`: 通常Releaseと測定Releaseを別DerivedDataから識別し、測定ReleaseだけをXcode直接installする。bundle version、build version、configuration、platform、codesign結果、commitを外部manifestへ記録する。network offline、CloudKit自動upload無効、DB初期状態、battery、thermal、storageを確認する。
3. adapterをUSBとbench電源へ接続するが、アプリから接続操作を行わず、physical OBD requestを0件に保つ。公式資料、実物maker/model、firmware cohort、USB serial候補、ECU simulator、12.0 V条件を照合する。候補が複数またはmacOS serial endpointが成立しない場合は停止する。
4. `bench_short`: Instruments記録を開始し、通常Production UIから確認済みendpointへ1回だけ接続する。cadence、PID集合、payload、timeout、retry、Raw、schema、SQLite設定を変更しない。tick 0からtick 8 terminalまで取得し、直後に通常切断する。60秒を超えた場合は後続要求を増やさず停止する。
5. graceful終了後、open batch、dispatch未確定request、未終了sessionが0件であることをread-only queryで確認する。DB、sidecar、PRAGMAは読むだけとし、checkpoint、VACUUM、journal mode、synchronous、auto-checkpointを変更しない。
6. run ID単位でsignpost、DB file、resource artifactをoffline joinし、manifest gate、request順、Raw対応、終了整合性を先に判定する。integrityが1件でも失敗したrunは性能値がbudget内でも不合格とする。

##### 4I.5 合格条件とrevision方針

初回runは、全static/local gate、Release install sanity、全整合性条件、全数値budgetを満たした場合だけ`bench_short_passed`とする。合格はnative macOS、同hardware/OS、同OBDLink EX firmware cohort、同USB serial、同bench、同build commitの1回だけに限定する。実車、iOS、Bluetooth、反復、耐久、background、process termination、checkpoint、CloudKit、TestFlight、一般リリースへは進まない。

運用後のrevisionは、観測値に合わせて同runの判定を変えず、次runから適用する。閾値緩和には製品上の根拠、risk、代替停止策、人間承認が必要である。閾値強化、artifact保持短縮、追加privacy除外も同じrevision履歴へ残す。adapter、transport、OS、hardware、bench、電源、network、DB初期状態の変更はいずれも新cohortとして`release_install_sanity`へ戻す。

### Phase 5: CloudKit同期対象と互換性

- 変更候補: `ConnectionSessionTransferPackage.swift`、`ConnectionSessionCloudMetadata.swift`、`CloudKitConnectionSessionTransferRepository.swift`、transfer codec/repository/synchronization tests。
- 依存方向: Domain transfer contractをData/CloudKitが実装し、Application use caseが同期を指示する。Platformは関与しない。
- 受入条件: payload format version、digest、session/account ownership、manifest/request/Raw整合、旧payload decode、未知version拒否、atomic stage/rollbackをtestする。
- 未確認: record対Asset、queryable field、容量、Production schema、retention/deletion連鎖。
- 人間承認: CloudKit data model、Development検証範囲、Production schema変更とProduction接続はさらに別承認。

### Phase 6: offline集計器拡張

- 変更候補: §7.4の`Tools/VehicleChangeDataQuality/`内だけ。
- 依存方向: Python standard libraryとoffline fileだけ。Production source/GRDB/CloudKit/networkへ依存しない。
- 受入条件: requested/result、window/mask/state/split/batch比較を匿名JSONへ決定的に出し、legacy/new schemaを明示分離する。
- 未確認: state grid、rare suppression、bootstrap方式、schema adapter versions。
- 人間承認: 匿名出力契約、候補grid、集計器変更後の実snapshot再分析範囲。

### Phase 7: synthetic fixture test

- 変更候補: §7.4のTests、必要ならREADMEだけ。
- 依存方向: testはOS一時directoryとPython standard libraryだけ。
- 受入条件: 全結果区分、window/mask/state/split、privacy、read-only、determinism、snapshot/working不変性、schema拒否を網羅する。
- 未確認: 実データ分布、端末性能、CloudKit、実transport結果。
- 人間承認: fixture coverageが計算契約だけの証拠であること。

### Phase 8: 実端末・実車での受入

- 変更候補: source変更なしを基本とし、承認済みacceptance記録と匿名出力を作る。必要な不具合修正は別phaseへ戻す。
- 依存方向: 通常Production取得経路だけを使用し、offline集計はcopyへ実行する。
- 受入条件: 安全な通常走行でmanifest→batch/request→Raw→終了→offline再測定が一致し、取得性能と容量を実測し、端末/Rawを変更しない。
- 未確認: 実車status mapping、background/切断、platform差、長期量。
- 人間承認: 実車実施範囲、端末、通常走行条件、ログ取得・保持・削除判断。

### Phase 9: 旧session互換性と明示的除外

- 変更候補: compatibility policy、Analysis入力選別use case、offline schema adapterとtests。UI変更は別依頼まで行わない。
- 依存方向: Domainが意味、Applicationが選別、Dataが読取、offline toolが匿名集計を所有する。
- 受入条件: 現在8 sessionを含むmanifest欠落sessionが`unknown/acquisitionRevisionUnavailable`となり、学習へ入らず、Raw再分析は`reanalyzedWithSnapshotRevision`と明示される。
- 未確認: 人間承認済み再decodeを許す範囲と監査記録。
- 人間承認: legacy除外を維持するか、限定PIDへ再decode承認経路を設けるか。

### Phase 10: rollback

- 変更候補: composition feature flag、repository reader compatibility、migration tests、CloudKit codec fallback tests。既存dataを削除するdown migrationは候補にしない。
- 依存方向: Appが新規write経路を停止でき、readerは既知旧versionを読み、Domain意味を変えない。
- 受入条件: 新規metadata writeを停止してもRaw取得の既存安全性を保ち、既存manifest/request行を破壊せず、旧reader/新reader matrixとCloudKit stage failureの復帰を検証する。
- 未確認: App Store/TestFlightでのversion跨ぎ順序、CloudKit schema rollback不可能部分。
- 人間承認: kill switch条件、forward-only migration、保持データ、release順序。

## 9. blocked事項とPrompt C解除条件

### 9.1 blockedのまま残す事項

- 現在8 session、60,505 Rawの取得時PID revisionと要求結果。
- 必要日数、距離、session数、window数、状態coverageのProduction閾値。
- window長、overlap、resampling、carry-forward、gap、missing処理の採用方式。
- idle、low-speed、cruise、acceleration、deceleration、warm-up、warmed、high-loadのProduction閾値。
- statistical baseline、distance方式、autoencoder、score、confidence、persistence、system mapping。
- app/policy/platform差の互換性と、整備前後の効果・因果。
- request metadataの実端末性能、保存容量、battery、CloudKit転送量。
- Production CloudKit Asset現存、復元、schema、TestFlight/実端末動作。

### 9.2 Prompt Cへ進むための具体的解除条件

次をすべて別証拠として満たすまでPrompt CのMLX feasibility spike実装へ進まない。

1. Phase 1〜4が承認・実装・testされ、**新規取得session**の各使用PIDについて取得時revision、bytes、formula identity、unit、range、ordered set、policy、request evidenceをimmutableに再現できる。
2. legacy sessionは取得時証拠がないまま学習へ混入せず、使用する場合はPID単位の明示的な`approvedRedecodeCompatible`契約を人間が承認する。
3. Phase 6〜7の匿名集計器がwindow候補、状態候補、missing/gap、split、batch比較を決定的に測定し、privacy validatorとsnapshot/working不変性が合格する。
4. 追加collection batchにより、独立したsession/time train・validation・test候補が各required PID/状態のsupportを持ち、同一session/重複window leakageなしで成立する。
5. 複数batchでPID coverage、cadence、gap、mask、状態coverageの分布とCIを比較し、人間が事前に選んだ安定基準を満たす。基準値はtest結果を見る前に固定する。
6. ML比較のprimary metric、guardrail、seed、停止条件、resource測定対象をtest splitを見る前に承認する。
7. Prompt C固有のMLX ownership、dependency、production/test path、新folder/standards変更について別のapproval gateを通過する。

metadata実装だけ、追加距離だけ、fixture成功だけ、window成立数だけでは解除しない。解除後も意味はfeasibility比較の開始許可であり、モデル精度、故障検知、実車妥当性、Production/CloudKit動作の承認ではない。

## 10. 次に人間が承認すべき最小phase

Phase 4H §4H.8の匿名performance event portとRelease相当signpost adapterは実装・local検証済みである。次の最小承認は、§4H.2〜§4H.7の未決定欄を埋めたうえで、`release_install_sanity`と安全な`bench_short`だけを実行する範囲である。対象端末・adapter・transport・bench、Release相当の署名・配布経路、短時間run条件、数値budget、artifact管理が固定されるまで実行は`no-go`とする。実車送信、反復・耐久、background、journal mode変更、checkpoint、CloudKit、常時有効化、一般リリースは、この次段階にも含めない。

人間は少なくとも次を確認する。

- 対象platform、端末、Release相当build、署名・配布経路。
- 資料と実物で確認済みのadapter、transport、benchまたは車両条件。
- event portとsignpost adapterの配置、no-op既定、有効化方式、privacy、許容overhead。
- 短時間、反復、耐久、lifecycleの実行条件と、事前固定するperformance・容量・battery・thermal budget。
- Production DBのruntime journal/synchronous/checkpoint条件を変更せず記録する方法と、checkpointを実行する場合の別承認。
- repository外artifactの保存先、アクセス権、保持期間、削除責任、匿名JSONだけをrepositoryへ置くかどうか。
- Raw優先失敗方針と、計測のためにProduction保存意味を変更しないこと。
- 最初の承認を接続前sanityと安全なbench短時間runまでに限定すること。

## 11. 証拠境界

本書と後続のfixtureは設計・計算契約の証拠に限る。次は常に別々に報告する。

- source/static checkとunit test
- synthetic fixture
- offline snapshot不変性とprivacy validator
- 物理端末copyと実車ログ量
- 実車での要求結果分類と取得性能
- Production CloudKit schema、Asset現存、復元
- hosted CI、TestFlight、UI、human review
- model学習、held-out精度、実車妥当性

いずれかの成功を他の成功として扱わず、未確認PID、故障、劣化、整備効果を推測しない。
