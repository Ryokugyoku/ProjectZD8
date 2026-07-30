# 登録車両専用変化検知 限定証拠実験仕様

## 1. 文書の責務、判定、根拠表記

本書の責務は、登録車両専用変化検知について、限定実車証拠から後続実験で比較する入力、特徴量、走行状態、初期基準完成条件、score、modelの候補と、その採用・停止条件を固定することである。本書はProduction仕様、学習実行、閾値、1,000 km、score方式、model方式を承認しない。

現時点の判定は **`revise`** である `[realDataObserved]`。候補比較の契約は作成できたが、取得時PID definition revision、走行状態coverage、独立したtrain/validation/testの十分量、縦断安定性がないため、Prompt CのMLX feasibility spike実装へは進まない `[blocked]`。

各項目の根拠区分は次の4種類だけを使用する。

| 区分 | 意味 |
| --- | --- |
| `requirementDerived` | [`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md)から直接導ける契約 |
| `realDataObserved` | [`VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md`](VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md)の匿名実車集計で確認済み |
| `hypothesis` | 同一入力・splitで後続実験が比較する候補。Production採用ではない |
| `blocked` | 現在の証拠では決定または評価できない |

同じ項目に複数の性質がある場合は、事実とそこから比較する仮説を別行にする。

## 2. 現在の証拠と制約

| 項目 | 現在の証拠 | 区分 | 実験上の制約 |
| --- | --- | --- | --- |
| 対象scope | 匿名account scope 1、登録車両1台、終了済み8 session | `realDataObserved` | 別VehicleIDや別accountへ一般化しない |
| 観測量 | 2記録日、37.0 km、Raw 60,505件、Raw観測約1.83時間 | `realDataObserved` | 季節、整備前後、長期trend、1,000 km候補を評価しない |
| 観測PID | Service 01の35 PID | `realDataObserved` | 未観測PIDを追加せず、35 PIDすべてを適格とみなさない |
| decode | 同一snapshotのrevision 2定義では全件が有限かつ宣言範囲内 | `realDataObserved` | 取得時互換性の証明ではない |
| revision | session/Rawに取得時PID definition revisionがない | `realDataObserved` | 現時点では全観測を学習から除外する |
| cadence | 高頻度4 PIDはmedian約0.54秒、低頻度31 PIDはmedian約6.17秒 | `realDataObserved` | 本番resampling値やgap閾値へ固定しない |
| gap候補の観測 | 10秒超interval 1,690件、`max(10秒, 3×median)`超450件、30秒超・60秒超0件 | `realDataObserved` | 要求分母がないため欠測率・timeout率と呼ばない |
| session偏り | session別Rawは2〜38,298件、median 1,922.5件 | `realDataObserved` | Raw行random splitと長sessionによる支配を禁止する |
| 状態coverage | 未測定 | `blocked` | 状態閾値、最低coverage、通知条件を決めない |
| Production復元 | DB上は8件uploadedかつmanifestあり、Asset現存・復元は未確認 | `blocked` | remote再現可能性の証拠にしない |

Raw payloadは派生値と独立した再解析根拠として保持し、missing、invalid、incompatibleを0へ置換しない `[requirementDerived]`。本書にはVIN、VehicleID、session ID、account ID、端末名、Raw payload、Manifest digest、個別走行時刻を掲載しない `[requirementDerived]`。

## 3. 入力PID manifest

### 3.1 manifest契約

各model generationは、順序付きService/PID、取得時definition revision、required byte count、formula/version、unit、validity range、feature-definition version、reference-period identity、training-log identity rangeをimmutable manifestとして保持する `[requirementDerived]`。同じService/PIDでもいずれかが異なれば互換入力とみなさない `[hypothesis]`。

以下の `semanticMappingVerified` は、現行seed/DB定義にある信号名、式、単位、範囲の対応だけを意味する。取得時互換性、車両挙動、故障、劣化、または電源・冷却・燃料吸気などの変化検知用system mappingを意味しない `[requirementDerived]`。

### 3.2 観測PID一覧

次の区分は下表の35 PID全行へ共通で適用する。`observedCandidate` と `excluded` は矛盾せず、前者は候補inventoryへの掲載、後者は現時点の学習・scoring入力からの除外を意味する `[requirementDerived]`。

| manifest区分 | 全35 PIDの値 | 区分 |
| --- | --- | --- |
| `observedCandidate` | `yes` | `realDataObserved` |
| `decodeVerifiedWithSnapshotRevision` | `yes: revision 2` | `realDataObserved` |
| `acquisitionRevisionUnavailable` | `yes` | `realDataObserved` |
| `semanticMappingVerified` | `signal definition only` | `requirementDerived` |
| `learningEligibilityNotEstablished` | `yes` | `blocked` |
| `excluded` | `yes: current training/scoring` | `requirementDerived` |
| `exclusionReason` | `acquisitionRevisionUnavailable` | `blocked` |

| Service/PID | 定義上の信号 | bytes | formula | unit | min...max | 現revision |
| --- | --- | ---: | --- | --- | ---: | ---: |
| `01/04` | calculated engine load | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/05` | engine coolant temperature | 1 | `A - 40` | `°C` | -40...215 | 2 |
| `01/06` | short term fuel trim bank 1 | 1 | `(A - 128) * 100 / 128` | `%` | -100...99.22 | 2 |
| `01/07` | long term fuel trim bank 1 | 1 | `(A - 128) * 100 / 128` | `%` | -100...99.22 | 2 |
| `01/0B` | intake manifold pressure | 1 | `A` | `kPa` | 0...255 | 2 |
| `01/0C` | engine speed | 2 | `(A * 256 + B) / 4` | `rpm` | 0...16,383.75 | 2 |
| `01/0D` | vehicle speed | 1 | `A` | `km/h` | 0...255 | 2 |
| `01/0E` | timing advance | 1 | `A / 2 - 64` | `°` | -64...63.5 | 2 |
| `01/0F` | intake air temperature | 1 | `A - 40` | `°C` | -40...215 | 2 |
| `01/10` | mass air flow rate | 2 | `(A * 256 + B) / 100` | `g/s` | 0...655.35 | 2 |
| `01/11` | absolute throttle position | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/15` | oxygen sensor B1S2 voltage | 2 | `A / 200` | `V` | 0...1.275 | 2 |
| `01/1F` | run time since engine start | 2 | `A * 256 + B` | `s` | 0...65,535 | 2 |
| `01/21` | distance with MIL on | 2 | `A * 256 + B` | `km` | 0...65,535 | 2 |
| `01/24` | oxygen sensor 1 equivalence ratio | 4 | `(A * 256 + B) / 32768` | `ratio` | 0...1.99997 | 2 |
| `01/2E` | commanded evaporative purge | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/2F` | fuel tank level | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/30` | warm-ups since codes cleared | 1 | `A` | `count` | 0...255 | 2 |
| `01/31` | distance since codes cleared | 2 | `A * 256 + B` | `km` | 0...65,535 | 2 |
| `01/33` | absolute barometric pressure | 1 | `A` | `kPa` | 0...255 | 2 |
| `01/34` | oxygen sensor 1 equivalence ratio/current | 4 | `(A * 256 + B) / 32768` | `ratio` | 0...1.99997 | 2 |
| `01/3C` | catalyst temperature B1S1 | 2 | `(A * 256 + B) / 10 - 40` | `°C` | -40...6,513.5 | 2 |
| `01/42` | control module voltage | 2 | `(A * 256 + B) / 1000` | `V` | 0...65.535 | 2 |
| `01/43` | absolute load value | 2 | `(A * 256 + B) * 100 / 255` | `%` | 0...25,700 | 2 |
| `01/44` | commanded equivalence ratio | 2 | `(A * 256 + B) / 32768` | `ratio` | 0...1.99997 | 2 |
| `01/45` | relative throttle position | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/46` | ambient air temperature | 1 | `A - 40` | `°C` | -40...215 | 2 |
| `01/47` | absolute throttle position B | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/49` | accelerator pedal position D | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/4A` | accelerator pedal position E | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/4C` | commanded throttle actuator | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/4D` | time run with MIL on | 2 | `A * 256 + B` | `min` | 0...65,535 | 2 |
| `01/4E` | time since codes cleared | 2 | `A * 256 + B` | `min` | 0...65,535 | 2 |
| `01/5A` | relative accelerator pedal position | 1 | `A * 100 / 255` | `%` | 0...100 | 2 |
| `01/5C` | engine oil temperature | 1 | `A - 40` | `°C` | -40...215 | 2 |

35 PIDの式・単位・値域は現行`StandardOBDPIDSeed`と同一snapshot DBのrevision 2定義に整合する `[realDataObserved]`。source URIの存在だけでは取得時revision互換性を証明しない `[requirementDerived]`。

将来、取得時manifestまたは人間が承認した再decode revisionを固定できたPIDだけを `excluded=no` へ遷移させる `[hypothesis]`。式、bytes、unit、rangeのrevision差分が不明、非有限、範囲外、別VehicleID、active session、DEMO/fixture/判定不能、Raw不在のいずれかはreasonを保持して除外する `[requirementDerived]`。

## 4. 時間窓、整列、欠測処理候補

### 4.1 固定規則

| 規則 | 区分 |
| --- | --- |
| windowは1 session内だけで作り、session境界を跨がない | `requirementDerived` |
| missing、invalid、gap、revision incompatibleを0へ置換しない | `requirementDerived` |
| valueとは別にPID別missing maskとgap maskを保持する | `requirementDerived` |
| 同じsessionの重複windowは同一splitへ置く | `requirementDerived` |
| timestampはRaw `observedAt`を基準とし、接続開始時刻をRaw開始とみなさない | `realDataObserved` |
| 同一batch時刻は同時観測候補として保持するが、到着順やPID個別latencyへ読み替えない | `realDataObserved` |

### 4.2 比較grid

| 項目 | 比較候補 | 採用条件 | 区分 |
| --- | --- | --- | --- |
| window長 | 10、30、60、120秒 | 低頻度PIDの最低観測数、状態純度、有効window数、推論時間のPareto比較 | `hypothesis` |
| overlap | 0%、50%、75% | leakageを増やさず、非重複window比でscore安定性が改善すること | `hypothesis` |
| 高頻度resampling | 0.5、1、2秒 | 約0.54秒medianを記述値として、補間量と情報損失を比較 | `hypothesis` |
| 低頻度resampling | 5、6、10秒、またはresampleなし | 約6.17秒medianを記述値として、直近値の古さと成立window数を比較 | `hypothesis` |
| alignment | window開始基準grid、中心時刻基準grid、event-time bin | 同一入力でdeterminism、coverage、境界感度を比較 | `hypothesis` |
| 直近値利用 | 不使用、`1×median`、`3×median`以内だけcarry-forward | stale値による状態誤分類を増やさず成立率が改善すること | `hypothesis` |
| gap mask | 10秒超、`3×median`、`5×median`、`max(10秒, 3×median)` | candidate別のwindow成立率とscore変動を比較 | `hypothesis` |
| 最低観測数 | PIDごとに2、3、5件、または期待観測数の50%/75% | estimatorに必要な点数と状態別coverageを同時に満たすこと | `hypothesis` |
| 短session | 全除外、1完全window未満を除外、count基準を併用 | min 2件sessionが特徴分布を作らないことを確認し、除外理由を保存 | `hypothesis` |

10秒超や相対gapは観測intervalの感度候補であり、欠測率、timeout率、異常を意味しない `[realDataObserved]`。異なるcadenceのPIDを同じwindowへ入れるのは、各PIDが個別の最低観測数または許容ageを満たし、maskを入力へ含め、低頻度値の複製が有効観測数を増やさない場合だけとする `[hypothesis]`。

線形補間、spline補間、session外carry-forwardは初期候補から除外する `[hypothesis]`。採用する場合は、実測値と補間値を区別するmask、最大補間幅、scoreへの影響を別実験で示す必要がある `[blocked]`。

## 5. 統計特徴量候補

### 5.1 PID単体

| 候補 | 目的 | 注意点・比較 | 区分 |
| --- | --- | --- | --- |
| median | window中心 | 外れ値に頑健。meanとの安定性比較 | `hypothesis` |
| IQR、MAD | robust dispersion | 定数windowでは0になり得るためmask/countと併用 | `hypothesis` |
| p10、p25、p75、p90 | 分布形状 | 観測数不足時は算出不能 | `hypothesis` |
| Theil-Senまたは時刻回帰slope | 時間変化 | cadence差と短window感度を比較 | `hypothesis` |
| first differenceのmedian/MAD/p90 | 局所変化 | resampling方式ごとに尺度が変わる | `hypothesis` |
| range、IQR/valid range、MAD/median等のvariation | 変動幅 | 0近傍の除算を避ける | `hypothesis` |
| valid observation count | 根拠量 | 値特徴とは別に保持 | `requirementDerived` |
| observed-bin rate | window内観測coverage | 要求分母がないためPID非応答率と呼ばない | `hypothesis` |
| missing mask rate、gap count、最大gap、window coverage | 品質 | anomaly scoreとconfidenceへ同じ意味で混ぜない | `requirementDerived` |

meanとstandard deviationは比較候補に残すが、session長を重みとして全行集約せず、window→sessionの二段階集約を比較する `[hypothesis]`。採用にはmedian/MAD系よりheld-out安定性、外れ値感度、長session支配のいずれも悪化しないことが必要である `[hypothesis]`。

### 5.2 多変量

同一または変換可能な確認済み単位の組だけについて、rank correlation、差、比、lagged associationを候補にできる `[hypothesis]`。0除算、時刻ずれ、単位不一致、低coverageの場合は算出不能とする `[requirementDerived]`。現在確認できる具体例は、同じ`%`単位の複数throttle/pedal候補、同じ`°C`単位の温度候補、同じ`ratio`単位のequivalence-ratio候補である `[requirementDerived]`。これらの相関を因果、故障、劣化、整備効果として説明しない `[requirementDerived]`。

system score用の電源・冷却・燃料吸気mappingは、現行の表示用`OBDPIDCategory`をそのまま流用せず、変化検知用mappingとして別途承認されるまで `blocked` とする `[blocked]`。

## 6. 走行状態候補と判定不能条件

状態は互いに排他的である必要はなく、初期比較ではmulti-label候補と単一優先順位候補を比較する `[hypothesis]`。どの方式でも判定不能は `unclassified` に保持し、正常値へ変換しない `[requirementDerived]`。

| 状態 | 使用候補PIDと確認根拠 | 現データでの成立可能性 | 比較する閾値候補 | 判定不能条件・追加データ | 区分 |
| --- | --- | --- | --- | --- | --- |
| `unclassified` | すべての適格PIDとmask | 常に表現可能 | 他状態不成立、競合、低coverage | reasonを`missingInput`、`gap`、`conflict`、`unsupported`へ分ける | `requirementDerived` |
| idle候補 | `01/0D` km/h、`01/0C` rpm | 両PIDは観測済みだが状態coverage未測定 | speed 0近傍の0/1/3/5 km/h、rpm正値と安定性 | 必要window数、停車中engine state、sensor量子化を追加測定 | `hypothesis` |
| low-speed候補 | `01/0D` km/h | PIDは観測済み | 上限20/30/40 km/h、車両内速度分位点 | 有効speed不足、window内状態遷移 | `hypothesis` |
| cruise候補 | `01/0D` km/h、任意で`01/11`/`45`/`47`/`49`/`4A`/`4C` % | 候補PIDは観測済み、同時coverage未測定 | speed slopeとvariationのp50/p75/p90、固定許容帯との比較 | 低頻度pedal/throttleのage超過、速度帯coverage不足 | `hypothesis` |
| acceleration候補 | `01/0D`の時間slope、任意でpedal/throttle % | speedは高頻度観測済み | 正slopeの固定小値と車両内p75/p90比較、連続bin数 | speed gap、短window、時刻逆転、状態coverage不足 | `hypothesis` |
| deceleration候補 | `01/0D`の時間slope | speedは高頻度観測済み | 負slopeの絶対値についてp75/p90と固定小値を比較 | accelerationと同じ。brake状態は未保存のため推測しない | `hypothesis` |
| warm-up候補 | `01/05` coolant °C、`01/1F` runtime s、任意で`01/5C` oil °C | 3 PIDは観測済み、開始直後coverage未測定 | 温度上昇slope、開始値からの差、plateau到達前の組合せ | cold-start相当の外部根拠、十分な開始時点、ambient差が必要 | `hypothesis` |
| warmed候補 | `01/05` coolant °C、任意で`01/5C` oil °C | 候補PIDは観測済み、plateau分布未測定 | absolute温度候補と個体内plateau/低slope候補を比較 | 2日だけで温度閾値を固定しない。季節・走行時間を追加 | `hypothesis` |
| high-load候補 | `01/04` calculated load %、`01/43` absolute load %、任意で`01/0C` rpm | load/rpmは観測済み、状態coverage未測定 | PID別p80/p90/p95、持続時間、固定%候補を比較 | 04と43を同じ尺度とみなさない。高負荷実在coverageが必要 | `hypothesis` |

「PIDが観測された」は状態が測定済みという意味ではない。現匿名集計から確認できるのは、候補入力が7/8または8/8 session・2/2記録日に存在することまでで、各状態のwindow数、時間、session、日、距離coverageはすべて未測定である `[realDataObserved]`。

状態ごとの最低coverageは、候補ごとに有効window数、総時間、session数、記録日数、距離、全候補状態に対する比率を出し、bootstrap confidence intervalと追加収集batch間の安定性を比較して決める `[hypothesis]`。単一の率だけで完成判定しない `[requirementDerived]`。

## 7. 初期基準完成条件候補

すべての軸を独立して記録し、1つでも採用閾値未満なら `insufficientData` を維持する `[requirementDerived]`。

| 軸 | 比較候補・測定 | 採用条件 | 現状 | 区分 |
| --- | --- | --- | --- | --- |
| 走行距離 | 500/1,000/1,500 km到達時snapshot比較 | validation安定性と状態coverageが頭打ちになる最小候補 | 37.0 km | `hypothesis` |
| 記録日数 | 累積日ごとのfeature/score分布差 | 追加日で分布差とCI幅が安定 | 2日 | `blocked` |
| 終了済みsession数 | 累積sessionごとのsplit成立性 | train/validation/testに独立sessionを配分できる | 8件 | `blocked` |
| 有効window数 | 状態別・PID別・session別件数 | 少数sessionに集中せずmetric CIが許容範囲 | 未測定 | `blocked` |
| PID coverage | manifest PIDごとのsession/日/window coverage | required PIDすべてが採用下限以上 | 2 PIDは8/8、33 PIDは7/8。window未測定 | `realDataObserved` |
| 状態別coverage | 時間、window、session、日、距離を併記 | required状態すべてが採用下限以上 | 未測定 | `blocked` |
| missing/gap | mask pattern、最大gap、候補別成立率 | 追加batch間で分布が安定しscoreを支配しない | interval候補だけ測定済み | `blocked` |
| 取得時revision互換性 | acquisition manifestとの完全一致 | 全入力PIDで一致または承認済み再decode | 全35 PIDで不足 | `blocked` |
| app version/端末互換性 | version/platform cohort別feature分布とdecode契約 | cohort差を説明またはcompatibleとして検証 | 未保存/端末個体差不明 | `blocked` |

1,000 kmは要件上の初期計画候補であり採用値ではない `[requirementDerived]`。距離へ到達しても日数、session、state、revision、versionのいずれかが不足すれば完成しない `[requirementDerived]`。

## 8. score、confidence、persistence、trend候補

### 8.1 結果状態

次の状態を排他的なanalysis outcomeとして保持する `[requirementDerived]`。

| 状態 | 意味 |
| --- | --- |
| `scored` | compatible inputと十分なcoverageでscoreを算出 |
| `insufficientData` | 必要量または状態coverage不足 |
| `incompatibleInput` | manifest、revision、feature、model/runtime不一致 |
| `analysisFailure` | decode後の計算、model load、推論等の失敗 |

`insufficientData`、`incompatibleInput`、`analysisFailure`をscore 0として保存・表示しない `[requirementDerived]`。

### 8.2 集約候補

| 層 | 比較候補 | 採用条件 | 区分 |
| --- | --- | --- | --- |
| PID単体変化量 | robust z-score絶対値、quantile distance、Mahalanobis/距離、reconstruction error | held-out stability、missing robustness、説明可能性 | `hypothesis` |
| system score | system内max、p90/p95、top-k mean、validation済みweight | 確認済みmappingだけを使用し大変化を希釈しない | `hypothesis` |
| 総合score | system max、上位percentile、softmax/log-sum-exp、重み付きmax | 単純平均より局所大変化を保持しfalse alertを抑える | `hypothesis` |
| confidence | coverage、reference support、calibration error、input compatibilityを別値化 | scoreの減算に使わず、observed outcomeと分離 | `requirementDerived` |

現時点では変化検知用system mappingが未承認なので、全PIDを `other verified numeric signal` 候補として扱い、電源・冷却・燃料吸気scoreは `notAvailable` とする `[blocked]`。mappingが承認されたPIDだけを該当systemへ移し、同一PIDの二重計上規則もmanifestに固定する `[hypothesis]`。

### 8.3 時間的状態

| 概念 | 候補契約 | 区分 |
| --- | --- | --- |
| single-session deviation | 1終了session内のeligible condition score。履歴へ残せるがpersistent通知を発生させない | `requirementDerived` |
| persistent change | 独立session、複数日、比較可能状態での再現回数、k-of-n、EWMA/CUSUMを比較 | `hypothesis` |
| long-term trend | 固定reference generationで距離・時間intervalごとのrobust slopeを比較 | `requirementDerived` |
| interval | 1,000 kmを含む500/1,000/1,500 km、または日/session基準を比較 | `hypothesis` |

persistence候補は、同じ長session内の重複windowだけで成立させない `[requirementDerived]`。採用にはfalse alerts per drive、insufficient-data frequency、状態別score安定性、recurrence適用前後の通知候補数をheld-out sessionで報告する `[requirementDerived]`。

## 9. statistical baselineと小型autoencoderの比較契約

この工程では学習しない `[requirementDerived]`。後続比較は以下を完全に共通化する。

| 契約 | 内容 | 区分 |
| --- | --- | --- |
| input | 同一ordered PID manifest、feature version、normalization、eligible window | `requirementDerived` |
| split | 同一session/time train・validation・test割当 | `requirementDerived` |
| missing | 同一missing/gap mask。model固有imputationは追加featureとして記録 | `requirementDerived` |
| metrics | false alerts/drive、insufficient frequency、状態別安定性、PR-AUC等のlabel可能metric、calibration error | `requirementDerived` |
| resources | artifact/model size、training wall time/peak memory、Mac/iPhone inference time/peak memory | `hypothesis` |
| determinism | seed、library/runtime、hardware、precision、repeat数を記録 | `hypothesis` |
| failure | insufficient、incompatible、training failure、inference failureを別集計 | `requirementDerived` |

比較候補は次のとおりである。

1. median/MADのrobust z-scoreをPID/feature単位で算出し、max、p90/p95、top-kで集約する statistical baseline `[hypothesis]`。
2. robust-scaled feature vectorに対するEuclidean、Manhattan、diagonal Mahalanobis、条件別nearest-centroid/kNN distance `[hypothesis]`。
3. 1〜3 hidden layer、bottleneckを入力次元の25%/50%、parameter数上限を複数候補とする小型autoencoder `[hypothesis]`。

autoencoderはbaselineより常に優れると仮定しない `[requirementDerived]`。採用には、同一test splitで主要品質metricを改善し、calibration、failure率、model size、training/inference時間、determinism、説明可能性のguardrailをすべて満たす必要がある `[hypothesis]`。改善が再現しない、test leakageがある、resource budgetを超える、baseline同等以下なら不採用または `revise` とする `[hypothesis]`。

resource budgetの数値は対象Mac/iPhoneと実装方式の測定前には決めない `[blocked]`。

## 10. splitとleakage防止

以下は実験仕様として固定する。

1. splitはRaw行単位でなくsession・時間単位で行う `[requirementDerived]`。
2. 同じsessionの隣接windowをtrainとtestへ分けない `[requirementDerived]`。
3. 同じ走行の重複windowを別splitへ入れない `[requirementDerived]`。
4. model/hyperparameter/threshold selectionはvalidationだけを使い、testを使わない `[requirementDerived]`。
5. 整備後データを整備前reference学習へ混入させない。境界が確認できない場合は整備効果評価をしない `[requirementDerived]`。
6. 将来時点のmetadata、状態、終了結果を過去windowのfeatureへ使わない `[requirementDerived]`。
7. 同一登録車両だけを対象とし、別VehicleID・別accountを混ぜない `[requirementDerived]`。
8. normalization、imputation、feature selection、confidence calibrationはtrainでfitし、validation/testへ固定適用する `[requirementDerived]`。
9. overlap windowの同一source intervalはgroup IDで束ね、必ず同一splitへ置く `[hypothesis]`。
10. 時間順にtrain→validation→testを配置し、必要なら複数rolling-origin splitで再現性を確認する `[hypothesis]`。

現在は2記録日しかなく、独立した時間splitで季節・日差を評価できない。8 sessionを形式的に分割しても十分な状態coverageを保証できないため、評価用splitは `blocked` である `[blocked]`。

## 11. 追加データ収集計画

固定した必要日数・距離・session数ではなく、収集batchごとに分布安定性を再測定する `[hypothesis]`。

| 追加軸 | 記録する比較 | 安定判定候補 | 区分 |
| --- | --- | --- | --- |
| 日数・距離・session | 累積batchごとのfeature分布、状態coverage、split成立性 | 前batchとのWasserstein/KS距離、median/IQR差、bootstrap CI幅 | `hypothesis` |
| 走行時間帯 | 時間帯を粗い匿名bucketで集計 | bucket間coverageとscore差。個別時刻は出力しない | `hypothesis` |
| 異なる状態 | 状態別window・時間・session・日・距離 | required状態の最小supportと追加batchでの再現 | `hypothesis` |
| 短/長session | 長さquantile別のwindow成立率・score | 特定長さへの偏りと除外感度が安定 | `hypothesis` |
| PID coverage | PID別session/日/window coverage | ordered setがbatch間で再現 | `hypothesis` |
| cadence/gap | PID別median/p95/max、全gap候補件数 | 分布距離と候補選択が複数batchで安定 | `hypothesis` |
| app version | version cohort別decode/coverage/feature分布 | manifest互換または明示的非互換を確定 | `blocked` |
| polling policy | ordered PID set、cadence cohort、要求/非応答記録 | policy差の影響を分離 | `blocked` |
| 端末差 | 個人情報でないstable installation cohort | 同platform内差を匿名比較 | `blocked` |
| 整備前後 | 実在し、ユーザーが境界を確認した場合だけ別period化 | 混入なしでresponseを記述。因果を断定しない | `blocked` |

次回収集は、現在の2日・37 km・8 sessionへ、異なる日、短/長session、低速・巡航・加減速・warm-up候補を含むことを目指すが、安全でない走行や意図的な高負荷操作を要求しない `[requirementDerived]`。追加距離・日・sessionの終了数値は、各batchの安定性curveがplateauするまで決めない `[hypothesis]`。

## 12. 取得時metadata不足への対応計画

Production Swift、migration、CloudKit schemaは本工程で変更しない `[requirementDerived]`。以下は独立した後続phase候補である。

| metadata | 保存責務候補 | 必要性・互換性 | 個人情報risk | 区分 |
| --- | --- | --- | --- | --- |
| app version | session acquisition manifest | 生成code世代を分離 | 低。version文字列のみ | `hypothesis` |
| schema version | session acquisition manifest | decoder/storage互換判定 | 低 | `hypothesis` |
| polling policy version | acquisition manifest | cadence・要求集合差を分離 | 低 | `hypothesis` |
| ordered PID set | acquisition manifest | 要求分母と入力順を再現 | 低。PID自体は非個人情報 | `hypothesis` |
| PID definition revision | PIDごとのacquisition manifest | 取得時decode契約を固定 | 低、必須 | `requirementDerived` |
| required byte count | PID definition snapshot | payload互換性 | 低 | `requirementDerived` |
| formula/version | versioned PID definition snapshot | 再decode再現性 | 低。式をversion管理 | `requirementDerived` |
| unit | PID definition snapshot | feature尺度互換性 | 低 | `requirementDerived` |
| validity range | PID definition snapshot | invalid値除外 | 低 | `requirementDerived` |
| PID capability snapshot | acquisition manifest | unsupportedと未観測の分離候補 | 中。ECU fingerprint化を避け、必要最小PID集合へ縮約 | `hypothesis` |
| acquisition platform | session | platform差の集計 | 低。端末名を保存・出力しない | `realDataObserved` |
| 取得開始時刻 | session | session境界 | 中。個別時刻は機微情報として集計時に縮約 | `realDataObserved` |
| Raw取得開始・終了時刻 | session派生summaryまたはRawから再計算 | 接続時間の過大評価を防ぐ | 中。個別時刻を外部成果物へ出さない | `hypothesis` |
| model input manifest version | model generation manifest | model/input互換判定 | 低 | `requirementDerived` |

保存ownerの最終設計、migration、retention、CloudKit同期範囲は統合計画で別承認する `[blocked]`。端末名、adapter identity、VIN、VehicleID原値、account IDをmodel featureへ使用しない `[requirementDerived]`。

## 13. 未決定事項

以下はProduction値として未決定である。

- ordered PID採用集合と取得時revision互換性の解消方法 `[blocked]`
- window長、overlap、resampling、carry-forward age、最低観測数、gap閾値 `[hypothesis]`
- robust統計量、mean/std、差分、slope、多変量featureの採否 `[hypothesis]`
- 全走行状態の閾値、優先順位、最低coverage `[blocked]`
- 初期基準の距離、日数、session数、window数、状態coverage `[blocked]`
- 1,000 km intervalの採否 `[blocked]`
- 変化検知用system mapping、PID/system/overall score集約、calibration `[blocked]`
- persistent condition、通知閾値、long-term trend方式 `[blocked]`
- statistical baseline、distance baseline、小型autoencoderの採否とresource budget `[blocked]`
- app version、polling policy、端末、整備前後の互換性 `[blocked]`

## 14. 後続実験の採用・停止条件

### 14.1 実験開始条件

次をすべて満たすまで学習比較を開始しない。

1. 対象は同一account・同一VehicleIDで、DEMO/fixture/判定不能を除外できる `[requirementDerived]`。
2. 使用PIDごとに取得時revisionまたは明示承認された再decode revision、formula、bytes、unit、rangeをimmutable manifestへ固定できる `[requirementDerived]`。
3. window候補ごとの有効数と状態coverageを匿名集計し、train/validation/testへ独立session・時間を配分できる `[hypothesis]`。
4. privacy validator、同一入力の決定性、snapshot/working copy不変性が合格する `[requirementDerived]`。
5. 評価metric、primary decision metric、guardrail、seed、停止条件をtest確認前に固定する `[hypothesis]`。

### 14.2 採用条件

候補は、複数のtime/session splitで結果が再現し、状態別coverageとconfidence calibrationを満たし、false alerts/driveとinsufficient frequencyの事前guardrail内にあり、隣接window leakageがなく、resource測定とfailure状態が明示される場合だけ採用候補に進める `[requirementDerived]`。autoencoderはstatistical/distance baselineに対して再現可能な実益がない限り採用しない `[hypothesis]`。

### 14.3 停止・revise条件

revision互換性不明、privacy違反、VehicleID混在、split leakage、required状態不足、metric CI不安定、version/policy差を説明不能、testをmodel selectionへ使用、Raw不変性不一致のいずれかで停止する `[requirementDerived]`。追加batchで分布が安定せず候補順位が反転する場合は `revise` とし、閾値を固定しない `[hypothesis]`。

## 15. 現時点のgo / revise / no-go

| 対象 | 判定 | 理由 | 次の解除条件 |
| --- | --- | --- | --- |
| 限定証拠からの候補仕様作成 | `go` | 要件、匿名監査、35 PID現行定義、cadenceを分離して候補化できた | 本書のhuman review |
| Production特徴量・状態・score仕様 | `revise` | 状態coverage、縦断量、system mapping、閾値が未確定 | 追加ログと比較実験 |
| 現データでの学習入力 | `no-go` | 35 PIDすべてで取得時revision不在 | acquisition manifestまたは承認済み再decode契約 |
| Prompt CのMLX feasibility spike実装 | `no-go` | eligible inputと十分なsession/time splitが成立していない | §14.1を満たし、Prompt Cの配置・依存approval gateを別途通過 |
| Production / CloudKit / 実車妥当性 | `no-go` | 本工程では変更・接続・学習・推論を実施していない | 後続の独立phaseと各証拠gate |

本書の `go` は仕様候補のreviewへ進める意味だけであり、モデル精度、実車妥当性、Production動作、CloudKit復元、TestFlight動作を示さない。
