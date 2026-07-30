# 登録車両変化検知 実車ログデータ品質監査

## 技術要約

2026-07-28に、ユーザーが実車と確認したTestFlight版の登録車両1台を `A001 / V001` として匿名化し、物理端末から読み取り専用で取得したoffline SQLite snapshotを監査した。対象は8件の終了済みsession、2記録日、37.0 km、Raw 60,505件である。snapshotとworking copyは実行前後のfingerprintが一致し、匿名結果は2回の生成でbyte-for-byte一致した。`PRAGMA integrity_check=ok`、schema互換、孤立Raw 0件、重複sequence群0件、session概要件数・byte数不一致0件だった。

現在snapshotのPID定義で再decodeすると、観測された35 PID、Raw 60,505件はすべて `numericFinite` かつ宣言範囲内だった。しかし、取得時点のPID definition revisionがsession/Rawへ保存されておらず、観測量も2日・37 kmに限られる。走行状態coverage、季節・整備前後・端末差、1,000 km候補の妥当性は評価できない。工程3判定は **`revise`** とし、特徴量、走行状態閾値、初期基準距離、スコア、モデル方式は確定しない。

## 良好な整合性と変換結果は、まだ学習適格を意味しない

| 項目 | 匿名実測 | 解釈 |
| --- | ---: | --- |
| account / 登録車両scope | 1 / 1 | 他車両・他accountとの混在は観測されない |
| session | 8 | 全件終了済み、Domain表示状態は全件`completed` |
| 観測期間 | 2026-07-26〜2026-07-28 | 実際にRawが存在する記録日は2日 |
| 距離 | 37.0 km | 7 sessionで成立、1 sessionは不成立 |
| session時間 | 7,016.167秒（約1.95時間） | HOME接続開始から終了までの合計 |
| Raw観測時間 | 6,579.662秒（約1.83時間） | session内Raw最初〜最後の合計 |
| Raw | 60,505件 / payload 144,870 byte | SQLite全体のsnapshotは13,090,816 byte |
| 観測PID | 35 | 全件Service 01。現在snapshot revisionは35 PIDとも2 |
| 数値化 | 60,505件 | 現在snapshot定義では100%有限・宣言範囲内 |
| local Raw | 8 / 8 session | 全件`available`、実Raw件数と概要が一致 |
| Cloud状態 | 8 / 8 session | `uploaded`かつManifestあり。ただしProduction Asset現存・復元成功は未証明 |

数値化結果は次の排他的分類になった。

| 分類 | 件数 | 割合 |
| --- | ---: | ---: |
| `numericFinite` | 60,505 | 100.00% |
| `missingDefinition` | 0 | 0.00% |
| `unavailableFormula` | 0 | 0.00% |
| `insufficientBytes` | 0 | 0.00% |
| `invalidExpression` | 0 | 0.00% |
| `nonFinite` | 0 | 0.00% |
| `outOfDeclaredRange` | 0 | 0.00% |

この100%は、現在snapshotに保存されたrevision 2の定義で再decodeできたという記述的結果である。取得時revision、式・単位・範囲の取得時互換性、走行状態coverageを証明しないため、全60,505件の学習適格性は `notEstablished: acquisitionRevisionUnavailable` のままとする。

## 4つの高頻度PIDと31の低頻度PIDで取得周期が分かれる

| Service / PID | Raw件数 | session coverage | 記録日coverage | 間隔median | p95 | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `01/04` | 7,677 | 7/8 | 2/2 | 0.541秒 | 2.355秒 | 11.170秒 |
| `01/0C` | 7,681 | 8/8 | 2/2 | 0.541秒 | 2.356秒 | 11.170秒 |
| `01/0D` | 7,680 | 8/8 | 2/2 | 0.541秒 | 2.356秒 | 11.170秒 |
| `01/11` | 7,676 | 7/8 | 2/2 | 0.541秒 | 2.355秒 | 11.170秒 |
| 下記31 PID（各961件） | 29,791 | 各7/8 | 各2/2 | 6.173秒 | 10.529秒 | 21.231秒 |

各961件のPIDは `01/05`、`01/06`、`01/07`、`01/0B`、`01/0E`、`01/0F`、`01/10`、`01/15`、`01/1F`、`01/21`、`01/24`、`01/2E`、`01/2F`、`01/30`、`01/31`、`01/33`、`01/34`、`01/3C`、`01/42`、`01/43`、`01/44`、`01/45`、`01/46`、`01/47`、`01/49`、`01/4A`、`01/4C`、`01/4D`、`01/4E`、`01/5A`、`01/5C` である。

PID別間隔では10秒超が合計1,690件、30秒超と60秒超は0件だった。`max(10秒, 3×median)` 超は450件である。高頻度4 PIDの10秒超は各4件、低頻度31 PIDでは各54件だった。この差は複数cadenceのpolling構成と整合するが、要求送信・非応答を永続化していないため、欠測率やtimeout率とは呼ばない。

`batchElapsedNanoseconds` は高頻度4 PIDでmedian約255.9 ms、p95約2,082.5 ms、max約10,887.1 ms、低頻度31 PIDでmedian約2,000.7 ms、p95約4,746.1 ms、max約10,887.1 msだった。同一応答群で共有するbatch全体時間であり、PID個別応答時間ではない。

期間が2記録日しかないため、時系列chartは傾向を誤認させる。この監査では正確な分布表を採用し、日次trend chartは追加データ取得後へ保留する。

## session量の偏りと短い観測が比較可能性を制限する

session別Raw件数はmin 2、p10 114.7、median 1,922.5、p90 17,831.4、p95 28,064.7、max 38,298、IQR 8,696であり、極めて短いsessionと長いsessionが混在する。min 2件のsessionは走行状態や定常分布の学習単位にできない。

session時間とRaw観測時間の差は合計436.505秒（約7.28分）で、median 11.738秒、max 352.276秒だった。`endedAt-startedAt`だけを取得時間として使用すると全体で約6.2%過大になるため、後続測定はRawのmin/max時刻を併記する。

保存済み直接終了原因は `userDisconnected` 2件、`vehicleNoResponse` 5件、`connectionLost` 1件だった。後者6件はすべてreview decisionが`userInitiated`で、Domain表示状態は8件とも`completed`になる。通信上の直接原因とユーザー確認済み終了区分は別々に保持・集計する必要がある。

## 監査範囲、入力、metric定義

- cohort: ユーザーが実車と確認した、同一account scope・登録車両1台の8 session。
- grain: session、Raw観測、Service/PID、PID連続観測間隔。
- 観測期間: Raw `observedAt` のUTC日付min/max。記録日数はRawが1件以上あるUTC distinct日数。
- session時間: `endedAt-startedAt`。Raw観測時間はsession内 `max(observedAt)-min(observedAt)`。
- 距離: 有限かつ0以上で、終了値が開始値以上の場合の差。距離source enumは保存されないため採用元は未確定。
- PID coverage: 対象PIDが1回以上観測されたsession数または記録日数を分子とする。要求分母がないため非応答率は算出しない。
- interval: 同じsession・同じService/PID内で観測時刻を昇順にした隣接差。session境界を跨がない。
- percentile: Hyndman-Fan type 7。
- 実車分類: DB値から推測せず、ユーザー確認を非公開scope manifestへ固定。

入力はアプリ終了後に物理端末のApplication Support directoryを1回だけ複製したoffline snapshotである。SQLite本体だけが存在し、copy元にもWAL/SHMは存在しなかった。snapshotとworking copyはSHA-256、size、mtime、file setを非公開manifestで照合した。

## 読み取り専用かつ匿名の測定方法

1. `devicectl device copy from`でTestFlight app data containerのApplication Supportを空の非公開一時directoryへ複製した。
2. TestFlight版の削除、更新、Debug版上書き、アプリ再起動、CloudKit接続を行わなかった。
3. snapshot全体をworking copyへ複製し、両方のwrite bitを除いた。
4. Python standard library `sqlite3`をURI `mode=ro`、`query_only=ON`、`trusted_schema=OFF`で使用した。
5. integrity、exact schema、親子整合性を先に検証し、parameterized SELECTだけで集計した。
6. 非公開manifestのaccount、VehicleID、session IDを結果へ写さず、`A001 / V001`へ置換した。
7. 禁止key、UUID形状、長いhex、manifest原値の混入をprivacy validatorで拒否した。
8. 同じ入力から2回生成したcanonical JSONがbyte-for-byte一致することを確認した。
9. 実行後にsnapshotとworking copyのfingerprintが実行前と一致することを確認した。

## データ品質上の懸念と下流リスク

| 重要度 | 懸念 | 証拠 | 学習・評価への影響 | 最小の次対応 |
| --- | --- | --- | --- | --- |
| High | 取得時PID revisionがない | 全35 PIDはsnapshot revision 2で再decode | 式・単位・範囲の世代互換性を証明できない | sessionまたはRawへ取得時definition manifestを永続化する設計を後続phaseで検討 |
| High | 縦断量が不足 | 2日、37 km、8 session | 走行状態、季節、整備前後、1,000 km候補、長期trendを判断できない | 同一車両で日・距離・状態を増やして再測定 |
| Medium | session量が強く偏る | 2〜38,298 Raw、median 1,922.5 | 短sessionが分布を不安定化し、長sessionが支配する | session単位splitと最低観測量候補を実データ感度比較する |
| Medium | 33 PIDが1 sessionで未観測 | 33 PIDは7/8、2 PIDだけ8/8 | 固定入力manifestの完全性とmissing maskが必要 | 欠測maskを維持し0補完しない。追加sessionで再現性を測る |
| Medium | 10秒超intervalがある | 1,690 interval、ただし30秒超0 | window内coverageが不均一になり得る | cadence別にgap候補を比較し、欠測率とは呼ばない |
| Medium | batch時間をPID latencyにできない | batch max約10.9秒、同一batchで共有 | 個別応答性能やtimeoutを誤って推定する危険 | request/nonresponse/batch identityの将来保存を検討 |
| Medium | Production復元が未確認 | 全8件uploaded/Manifestあり | local削除後の学習再現性は未証明 | 別の明示承認工程で1 sessionのProduction復元E2Eを検証 |
| Low | session時間がRaw時間を上回る | 合計約7.28分、max約5.87分 | 接続時間を学習coverageに使うと過大 | Raw観測時間を主指標として併記 |

この監査は記述的なデータ品質評価であり、車両状態、故障、劣化、整備効果、因果関係を推定しない。

## 工程3判定はrevise

以下は合格した。

- 物理端末snapshot取得、integrity、schema、privacy、scope分離
- 複数終了sessionと複数記録日の実車Raw
- Raw parent、件数、byte数、sequenceの整合
- 現在snapshot定義による35 PID・60,505件の有限範囲内decode
- 再現可能な匿名集計と入力不変性

一方、取得時revision、十分な日数・距離・状態coverage、Production復元、複数端末・app version互換性が不足する。このためPrompt Bの特徴量・走行状態・スコア仕様を確定するには進まず、限定証拠として仮説と追加測定項目を整理できる段階に留める。

## 次に必要な測定

1. 同一登録車両で、異なる日・距離・走行条件の追加sessionを収集し、同じ集計器で差分を測る。
2. sessionごとのPID definition revision、app version、schema version、polling policy、PID capability snapshotを将来どう固定するか設計する。ただしこの監査ではmigrationしない。
3. 確認済み車速・回転数・温度・負荷PIDだけで、走行状態候補の時間・session・日coverageを測る。閾値は比較後に決める。
4. session単位・時間単位のsplitで、短session除外候補とmissing maskの感度を測る。
5. Production CloudKitからlocal削除済みRawを1件復元し、digest、sequence、decode、入力manifest再現性を別証拠として確認する。
6. 1,000 km候補へ到達する日数・session数・状態coverageは、実際に距離を蓄積してから評価する。

## 追加で答えるべき問い

- どの取得時metadataをRaw不変性を壊さずにmodel input manifestへ固定するか。
- 2 cadenceのpollingが意図したpolicyか、実装version間で変更されるか。
- min 2件のような短sessionをどの段階で除外し、除外理由をどう保存するか。
- 33 PIDの1 session欠測が接続時間、capability、polling開始、通信中断のどれに由来するか。
- Production復元後も同じ匿名集計結果を再現できるか。
