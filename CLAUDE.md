# ProjectZD8 / RevTorque Insight

OBDアダプター経由で車両テレメトリを取得・記録・分析する SwiftUI アプリ(iOS + macOS。アプリ本体は単一のマルチプラットフォーム target `ProjectZD8`、ほかに Live Activity 用の拡張 target `RecordingSessionLiveActivity` とテスト target 2つ)。製品名は **RevTorque Insight**。target・bundle ID・永続化パス等の識別子は `ProjectZD8` のまま(改名は要合意)。

## Build / Test

Xcode 26.4+(deployment target iOS/macOS 26.4)、scheme `ProjectZD8` のみ、GRDB.swift 7.x、XCTest。filesystem-synchronized group のためファイル追加・移動で `project.pbxproj` 編集は不要。

```sh
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' build
python3 Tools/XcodeTestRunner/run_xcodebuild.py --limit 600 --kill-pattern 'Build/Products/.*/RevTorque Insight' -- \
  xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' -enableCodeCoverage NO test -only-testing:ProjectZD8Tests/<TestClass>
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'generic/platform=iOS Simulator' build
PYTHONPATH=Tools/VehicleChangeDataQuality python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
ruby .github/testflight_build_publisher_test.rb
python3 Tools/CodeMetrics/check_swift_metrics.py --changed-since origin/main
python3 -m unittest discover -s Tools/CodeMetrics/Tests -v
python3 -m unittest discover -s Tools/XcodeTestRunner/Tests -v
```

- ローカルの `xcodebuild test` は必ず上の形(`Tools/XcodeTestRunner/` が1本ずつ・時間上限つきで実行する。仕様は同 README)で、前面で1回ずつ呼ぶ。担当へのブリーフにもこの形を書く。
  - `-enableCodeCoverage NO` を外さない(外すとテスト後のカバレッジ回収で約80分止まる)。CI のカバレッジ設定は変えない。
  - `--limit`(秒)は対象を絞った実行で 600 が目安。実装を壊しての確認は対象クラスを絞る。終了コード 124(時間上限)・125(ロック待ち超過)は再試行せず報告する。
  - バックグラウンドで起動して `pgrep` で終了を待つループを作らない(自分のコマンド行に一致して回り続ける)。
- 複雑さチェック(`Tools/CodeMetrics/`、仕様は同 README。要 `pip install --user -r Tools/CodeMetrics/requirements.txt`): Swift の編集のたびにフック(`.claude/settings.json`)が走り、上限超過の `error:` だけを Claude に返す。CI も変更ファイルを確かめる。
  - 最終レビューでは `--changed-since origin/main` を実行し、`warning:`(触ったファイルに残る既存の超過)も確かめる。未追跡の新規ファイルは含まれないので、先に `git add -N <ファイル>` するか引数で直接渡す。
  - 既存の超過は `baseline.json` で許容し、値が増えたらエラー。ベースラインは超過を解消した時だけ `--update-baseline` で更新する。
- 実行範囲: Swift は変更した型の `-only-testing:ProjectZD8Tests/<TestClass>`(複数可)、`Tools/` 配下は変えたツールの unittest 全件、`.github/` は ruby テスト。PR 説明の「テスト」欄にコマンドと結果を書く。
- CI: `tests.yml`(PR と main push。macOS 単体テスト全件 `-only-testing:ProjectZD8Tests`、UI テストは署名なしで起動不可のため対象外。Ruby・Python テストも実行。Xcode 26.6、`CODE_SIGNING_ALLOWED=NO`)、`testflight.yml`(main で手動、iOS/macOS アーカイブ→TestFlight)。
- ローカルのビルド/テスト成功を、見た目・実機・実アダプター・CloudKit 本番・CI の成功として報告しない。
- CloudKit のレコード種別・フィールド・クエリ条件を足した変更は、`Documentation/CLOUDKIT_SCHEMA_DEPLOYMENT.md` の表を同じ PR で更新し、PR 説明に「本番スキーマへの反映が必要」と書く。本番環境は種別を自動作成しないので、反映前の TestFlight 版ではその保存が必ず失敗する。

## アーキテクチャ

`Platform → Application → Domain ← Data`。全依存は `App/Composition/{IOS,MacOS}ApplicationComposition.swift` で組み立てる。

| 層 | 置くもの | 禁止 |
| --- | --- | --- |
| `App` | エントリ、DI | 業務ルール・画面レイアウト |
| `Domain` | Entities / ValueObjects / Policies / Repositories(契約) / Errors | 他層・SwiftUI・GRDB・SwiftData の import |
| `Application/Features/<F>` | Actions / State / UseCases / Ports | 具象 Data アダプター・Platform・SwiftUI |
| `Data` | GRDB、CloudKit、OBD/Serial/Bluetooth、ファイル、Keychain 等 | Platform・View |
| `Platform/{iOS,macOS}` | AppShell、Features/<F>/{Views,Presentation} | Data・GRDB・SQL・デバイスAPI直接アクセス |
| `Shared` | 複数オーナーが使う小部品のみ(`DesignSystem/Components`) | 機能ロジック |

- View は描画・UI一時状態・型付き Action 送出のみ。Presentation が Action を Application 呼び出しへ変換する。
- iOS と macOS の画面は別ツリー・別型。共有 View 内の大きな `#if os()` 分岐は禁止。同じロジックを両 OS にコピーせず、ロジックと汎用部品だけを共通化する。
- 副作用(時刻・ID・永続化・通信・デバイス)はポート経由で注入。デバイス入力は use case 経由で永続化・表示・分析へ流し、Raw ログは派生分析結果と独立に保持。
- 失敗(未接続・モデル不在・推論失敗等)を成功や空データに潰さない。「接続済み」等の表示は state の裏付けがある時だけ。
- Feature 間は具象型に依存しない。横断ワークフローは所有 Feature を1つ決め、Domain 型か狭いポートで連携。
- `Helpers`/`Utils`/`Common`/広い `Manager` は作らない。新 Feature・トップレベルディレクトリは作る前にユーザーへ提案。
- `RecordingSessionLiveActivity/`(Live Activity の拡張 target)は Platform 層と同じ扱い: 描画だけを置き、業務ルール・Data・デバイスへ直接触れない。1ファイル1型で `RecordingSessionLiveActivity` を接頭辞にする。

## 段階的なモジュール化

業務のまとまり(コンテキスト)ごとに、ローカル Swift Package `Packages/` のモジュールへ少しずつ移す計画がある。進め方のルール・対応表・順番・状態は `Documentation/MODULARIZATION_PLAN.md` が正。状態が「未着手」のコンテキストの型は移さない。準備やモジュールへの移動に着手する時は、先に同文書の「進め方のルール」を読む。

## 画面の分割とフォルダ構成(単一責任)

型もファイルも「変更理由は1つ」で分ける。View に判定・整形・文言選択を溜めない。新規画面と、分割・改修で手を入れる画面に適用(既存画面は触る時に移行)。

- **1画面=1フォルダ**: 複数ファイルに分ける画面は `Platform/<OS>/Features/<F>/Views/<画面名>/`(OS 接頭辞と `View` 接尾辞を除いた名前。例 `Views/ConnectionHistory/`)。1ファイルで収まる画面は `Views/` 直下でよい。
- フォルダには画面ルート(`<OS接頭辞><画面名>View.swift`)とその画面専用の部品 View だけを置く。部品も1ファイル1型で、画面名を接頭辞に持つ(例 `MacOSConnectionHistoryHeroCard.swift`)。
- 画面ルートは部品の配置・ナビゲーション・alert/sheet の接続・Action 送出だけ。部品 View は描画に必要な値と Action 送出クロージャだけを受け取る(画面全体の state を渡すのは複数項目を読む部品に限る)。
- 表示ロジックは SwiftUI を import しない純粋型にする: iOS/macOS 共通の判定・整形・文言キー・alert 内容は `Application/Features/<F>/State/`(ローカライズキーは `String` で返し View で `LocalizedStringKey` に変換)、片方の OS だけのものは `Platform/<OS>/Features/<F>/Presentation/`。
- 複数画面で使う部品: 同一 Feature・同一 OS 内は `Views/Components/`、Feature/OS をまたぐなら機能知識を持たない汎用部品として `Shared/DesignSystem/Components/`。
- 目安: View ファイルは250行程度まで。超えたら分割を検討。
- テスト: 分離した純粋型は公開メソッド・計算プロパティごとに分岐と境界値を網羅する。SwiftUI の `body` は対象外とし、判定を純粋型へ出して検証する。

## Feature(Application と Platform で同名)

`Authentication`(Apple サインイン・資格復元・アクセスゲート) / `Settings`(アカウント設定と端末間同期、接続設定除く) / `DeviceConnection`(アダプター探索・接続・切断・接続設定) / `VehicleManagement`(車両の識別・登録・プロフィール・画像・同期・選択) / `Maintenance`(整備記録・写真・同期) / `LiveTelemetry`(リアルタイム表示) / `Logging`(取得セッション開始・記録・終了) / `LogHistory`(記録済みログ照会) / `Analysis`(記録ログの分析実行と結果) / `RoadRegulation`(交通規制データの取得・保存・検索と走行の突き合わせ)

## コード規約

- 全コード共通の上限(`Tools/CodeMetrics/` が判定。詳細は共通ルール §5): 1関数の循環的複雑度10・認知的複雑度15・制御構造のネスト3段・80行(計算プロパティと SwiftUI の `body` を含む)、1ファイルの関数20個・500行、1行160文字。
- 宣言に日本語 `///` DocC、メソッドには `責務:` の一文。
- 1ファイル1主要型、ファイル名=主要宣言名。例 `XxxUseCase`、`GRDBXxxRepository`、`XxxState`/`XxxAction`。プラットフォーム固有型は `IOS`/`MacOS` 接頭辞。
- テストは本番パスをミラー(`ProjectZD8/<path>/Foo.swift` → `ProjectZD8Tests/<path>/FooTests.swift`)。
- UI 文字列は `Resources/Localization/Localizable.xcstrings`。UI 寸法は `MacOSAppShellMetrics`/`IOSLoginMetrics` 等の Metrics 型に集約。
- アクセント色はシアン。オレンジは警告・ピーク用の小さな強調のみ。

## 見つけにくい場所

- DB スキーマ/マイグレーション: `Data/Persistence/GRDB/Database/ProjectZD8DatabaseMigrator.swift`(PID シード `StandardOBDPIDSeed.swift`、`ZD8OBDPIDSeed.swift`)
- `Unavailable*` Repository = DB 準備不可時に明示的失敗を返す代替。`Demo*` = デモモード用。
- ELM327: `Data/Devices/OBD/`。トランスポートは macOS `Data/Devices/Serial/`、iOS `Data/Devices/OBD/` と `Data/Devices/IOS*`。
- 取得証跡: Domain `ConnectionSessionAcquisition*` / GRDB `ConnectionSessionAcquisition*Record`

## 車両変化検知

`Documentation/VEHICLE_CHANGE_DETECTION_*.md`(要件の正は `..._REQUIREMENTS.md`)。オフライン品質ツール `Tools/VehicleChangeDataQuality/` は Python 標準ライブラリのみで製品コード非依存。「Prompt A〜F」は段階名(A=実ログ監査、B=特徴量/スコア仕様、C=macOS MLX spike、D=回顧的モデル評価、E=本番統合計画、F=統合実施)。C 以降は no-go、解除条件は `..._ACQUISITION_AND_COLLECTION_PLAN.md` §9。
