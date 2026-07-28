# Vehicle change detection Codex prompts

## 1. Document responsibility

This document provides copy-and-paste Codex requests that advance the approved
vehicle-specific change-detection requirements from evidence gathering through
reviewed product integration. Run them in order. Do not combine later prompts
before their named inputs exist.

Every request assumes the repository root is:

```text
/Users/ryokugyoku/Desktop/SourceCode/ProjectZD8
```

The requirements authority for this workflow is
[`VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md`](VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md).

## 2. Prompt A — audit real logs and PID readiness

Use this first. It combines stages 2 and 3 because data inventory and quality
coverage must be measured from the same source.

```text
ProjectZD8で、登録車両専用の変化検知に利用できる既存ログとPIDデータ品質を、読み取り中心で監査してください。

最初にAGENTS.mdとDocumentation/INDEX.mdを読み、Documentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.mdを要件 authority としてください。git status --shortを確認し、無関係な変更、とくに.github/workflows/testflight.ymlの既存変更へ触れないでください。

目的はモデル実装ではなく、実データから次を確認することです。

1. 実際に存在するログ保存形式、Raw復元経路、登録VehicleIDとの結合、PID定義とrevisionの保持方法
2. 変換式・必要byte数・単位が確認済みで、有限数値へデコードできるPID一覧
3. 登録車両ごとのセッション数、走行距離、取得時間、日数、サンプル数、取得周期、欠測率、デコード失敗率
4. セッション経過時間、車速、確認済み温度・回転数・負荷などから分類可能な走行状態と、状態別カバー率
5. 1,000kmの初期計画値が妥当か判断するための分布。ただし根拠なしに本番閾値を決定しないこと
6. 学習対象から除外すべきセッション・観測と、その機械判定可能な理由
7. 個人情報、VIN、アカウント識別子、Raw payloadを報告書へ露出しない匿名化方針

実車ログの場所や取得権限が確認できない場合、DEMOやテストfixtureを実車証拠として代用しないでください。その時点までのコード・スキーマ監査を完了し、必要なログの正確な取得元、ユーザー操作、読み取り専用抽出手順、必要容量を提示して停止してください。端末DB、CloudKit、Rawログを変更しないでください。

実データが利用可能な場合も、元データは変更せず、集計結果だけをDocumentation/VEHICLE_CHANGE_DETECTION_DATA_AUDIT.mdへ記録してください。報告書にはデータ出所、観測期間、登録車両ごとの匿名集計、PID readiness表、走行状態カバー率、欠測・偏り、利用可能性判定、未検証事項、次の特徴量設計で使える具体的入力を含めてください。

この工程ではMLX依存追加、学習、アプリ実装、DB migration、CloudKit変更を行わないでください。実行した検証と、実車・Productionで未確認の事項を分離して報告してください。
```

## 3. Prompt B — specify features, regimes, and scores

Run only after Prompt A has produced a real-data audit or an explicitly accepted
limited-evidence audit.

```text
Documentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.mdとDocumentation/VEHICLE_CHANGE_DETECTION_DATA_AUDIT.mdを根拠に、登録車両専用変化検知の特徴量・走行状態・スコア仕様を作成してください。

最初にAGENTS.md、Documentation/INDEX.md、必要なCoding StandardsとPlacement Rulesを読み、git status --shortで無関係な変更を保護してください。実ログ監査にないPID、式、単位、車両挙動を推測しないでください。

Documentation/VEHICLE_CHANGE_DETECTION_FEATURE_SPEC.mdへ、少なくとも次を決定または「実験で比較」として明示してください。

1. 車両ごとの固定入力manifestとPID revision互換性
2. 時間窓、overlap、時刻整列、欠測mask、外れ値・無効値処理
3. PID単体の統計特徴量と、意味を推測しない多変量関係特徴量
4. 実データで成立する走行状態分類と判定不能条件
5. 初期基準完成に必要な距離、日数、セッション数、状態別coverageの候補
6. 総合、電源、冷却、燃料・吸気、その他のスコア入力。ただし系統分類は確認済みmappingだけを使用
7. 単純平均で大きな系統変化を薄めない総合スコア候補
8. 信頼度、継続性、単発変化、長期trendを分離した状態モデル
9. 走行ごとの暫定評価と1,000km候補区間の確定方法
10. statistical baselineと小型autoencoderの比較実験条件
11. 学習・検証・test splitをsessionと時間で分離し、隣接sample leakageを防ぐ方法
12. 未確定閾値、必要な追加データ、採用判断基準

この工程ではプロダクションSwift、MLX依存、DB、CloudKit、UIを変更しないでください。仕様内の各決定を、要件由来、実データ由来、仮説、未決定のいずれかとして識別してください。
```

## 4. Prompt C — propose and build the macOS MLX feasibility spike

This prompt intentionally contains an approval gate. The current repository
rules name TensorFlow and do not pre-authorize an MLX production path.

```text
登録車両専用変化検知について、macOS限定のMLX Swift feasibility spikeを設計し、承認後に実装してください。根拠はDocumentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md、DATA_AUDIT.md、FEATURE_SPEC.mdです。

最初にAGENTS.md、Documentation/INDEX.md、Documentation/CODING_STANDARDS.md、Documentation/PLACEMENT_RULES.mdを全文読み、対象コードと直接依存、関連テスト、project設定を確認してください。git status --shortで既存変更を保護してください。

現在の規約はData/MachineLearning/TensorFlowを明記しています。コード変更前に必ず次を提示し、私の明示承認を待ってください。

1. MLX spikeの単一責務とTensorFlow境界との関係
2. 実験コードをproduction targetへ入れる必要があるか、独立した既存test targetで成立するか
3. 新directoryが必要な場合の正確なproduction/test path
4. Application analysis port、Domain、Data、Platform間の依存方向
5. CODING_STANDARDS.mdとPLACEMENT_RULES.mdをframework-neutralに改訂する案、またはMLXを明示する案
6. 追加dependency、対応platform、ライセンス、想定artifact形式と容量
7. spikeを削除・置換できるrollback方法

承認後は、実データを匿名かつ読み取り専用で入力できる再現可能なmacOS実験を実装してください。最低限、同一のtrain/validation/test splitでstatistical baselineと小型autoencoderを比較し、seed、特徴量version、input manifest、training configuration、metricsを記録してください。学習済みでないtest dataに対する結果を出してください。

新規・変更Swift declarationとmethodには日本語DocCと一文の「責務:」を付け、プロダクション取得・永続化を学習処理へ結合しないでください。iPhone学習、CloudKit、UI、Production model公開は行わないでください。

結果をDocumentation/VEHICLE_CHANGE_DETECTION_MLX_SPIKE_REPORT.mdへ記録し、ビルド、テスト、学習完了、評価、性能測定、実車妥当性を別々の証拠として報告してください。
```

## 5. Prompt D — run retrospective model evaluation

Run only when the spike is reproducible and the user has accepted the evaluation
dataset scope.

```text
承認済みMLX spikeと実ログを使い、登録車両専用変化検知のretrospective evaluationを実施してください。実装を拡張する前に、Documentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md、DATA_AUDIT.md、FEATURE_SPEC.md、MLX_SPIKE_REPORT.mdを読み、評価対象VehicleID、session範囲、整備記録との対応を匿名化して確認してください。

評価では次を必須にしてください。

1. 車両を混在させず、session・時間単位でtrain/validation/testを分離
2. statistical baselineとMLX候補を同じ入力・同じsplitで比較
3. 走行状態別のscore分布、安定性、判定不能率
4. 1走行あたりの誤警告候補数と、継続条件適用後の通知候補数
5. 1,000km候補区間でのtrend安定性と、別の区間幅に対する感度
6. PID欠測、PID revision変更、短いsession、偏った走行条件へのrobustness
7. 整備前後データが実在する場合だけ、そのscore応答。因果や劣化を断定しないこと
8. model size、training time、peak memory、Mac推論時間、iPhone推論実現性に必要な未検証事項
9. score calibration、confidence、persistent-change条件の候補と根拠
10. go、revise、no-go判定と、その判定を覆すために必要な追加データ

結果をDocumentation/VEHICLE_CHANGE_DETECTION_EVALUATION_REPORT.mdへ保存してください。Raw値、VIN、アカウント識別子などを文書へ出さないでください。この工程ではCloudKit、iPhone runtime、ユーザー通知、Production model公開を実装しないでください。評価用変更がある場合は最小scopeでテストし、実行した証拠と未検証事項を分離してください。
```

## 6. Prompt E — create the reviewed production integration plan

This is the gate between experimental evidence and product implementation.

```text
Documentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md、DATA_AUDIT.md、FEATURE_SPEC.md、MLX_SPIKE_REPORT.md、EVALUATION_REPORT.mdを根拠に、登録車両専用変化検知をProjectZD8へ統合する実行計画を作成してください。

この依頼ではまだ全機能を実装しないでください。AGENTS.md、Documentation/INDEX.md、CODING_STANDARDS.md、PLACEMENT_RULES.md、対象Featureと直接依存を確認し、現在の実装との差分を調査してください。

計画には独立してレビュー・検証できるphaseとして、少なくとも次を含めてください。

1. framework-neutralなDomain結果、reference period、model generation、manifest、confidence、failure状態
2. Application/Features/AnalysisのmacOS training/reconstruction/publication use caseとanalysis port
3. MLX Data adapter、artifact codec、model registry、atomic activation、rollback
4. GRDB migrationとRawから派生結果を分離したrepository
5. CloudKit private databaseでの車両別model artifact/manifest/result同期。Production schemaは別証拠とすること
6. iPhoneのartifact download、digest/compatibility/smoke inference、走行後推論、未解析session再処理
7. Settingsのaccount-scoped automatic downloadとdevice-scoped cellular permission
8. macOSの学習data review、再構築、validation、publication UI
9. iOS/macOS独立の総合・系統別・trend・confidence・insufficient-data表示
10. local model cache削除、車両削除、account erasure、remote artifact削除の契約
11. unit、integration、migration、sync、UI、accessibility、performance、real-device、Production CloudKitの検証matrix
12. feature flag、段階rollout、rollback、既存Analysis表示との互換性

各phaseについて、変更責務、具体的なproduction/test file候補、依存方向、migration、受入条件、実行コマンド、未検証事項を示してください。新directoryやFeature境界変更が必要なら、PLACEMENT_RULES.mdのapproval gateとして明示し、実装前に承認を求めてください。計画をDocumentation/VEHICLE_CHANGE_DETECTION_INTEGRATION_PLAN.mdへ保存してください。
```

## 7. Prompt F — execute one approved integration phase

Do not ask Codex to implement the whole integration plan in one change. Copy this
prompt once per approved phase and replace the placeholders.

```text
Documentation/VEHICLE_CHANGE_DETECTION_INTEGRATION_PLAN.mdの承認済みPhase <番号と名称> だけを実装してください。

承認記録または追加条件：
<ここに人間の承認内容を貼る>

AGENTS.mdの必須手順を守り、最初にDocumentation/INDEX.md、CODING_STANDARDS.md、PLACEMENT_RULES.md、Phaseの対象ファイルと直接依存、関連テスト、現在のgit statusを確認してください。無関係な変更を保持し、Phase外へscopeを広げないでください。

計画にあるDomain/Application/Data/Platform境界、車両ID分離、確認済みPID限定、Raw独立保持、失敗状態分離、iOS/macOS View分離を維持してください。新規・変更Swift declarationとmethodには日本語DocCと一文の「責務:」を付けてください。

最小の関連テストから始め、Phaseのriskに比例したbuild/testを実行してください。モデル学習、ローカル推論、Simulator、実機、実車、CloudKit Development/Production、UI runner、human visual review、hosted CI、TestFlightを別々の証拠として報告してください。未実施の証拠を成功扱いしないでください。

完了時に、変更ファイルと各責務、実行した検証と結果、未検証事項、既知の制約、次の未着手Phaseを報告してください。Phaseの受入条件を満たせない場合は、部分実装を成功扱いせず正確なblockerを示してください。
```

## 8. Sequencing rule

After each prompt, review its output before starting the next one. When the data
audit, feature specification, or evaluation changes an assumption, update the
requirements through an explicit documentation review rather than silently
carrying the old assumption into source code.
