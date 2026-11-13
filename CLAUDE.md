# ProjectZD8 / RevTorque Insight

OBDアダプター経由で車両テレメトリを取得・記録・分析する SwiftUI アプリ(iOS + macOS、単一マルチプラットフォームtarget)。
製品名は **RevTorque Insight**。target・bundle ID・永続化ディレクトリなどの技術識別子は `ProjectZD8` のまま(改名は別途合意が必要)。

## Build / Test

Xcode 26.4+(deployment target iOS / macOS 26.4)、scheme は `ProjectZD8` のみ、依存は GRDB.swift 7.x、テストは XCTest。
Xcodeプロジェクトは filesystem-synchronized group なので、ファイル追加・移動で `project.pbxproj` の編集は不要。
`xcode-select` が CommandLineTools を指す環境では `DEVELOPER_DIR` を付ける。プロビジョニングの無い環境では署名を無効にする。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# macOS ビルド・単体テスト(最初に試す最小チェック)
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO test -only-testing:ProjectZD8Tests/<TestClass>
# iOS ビルド
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build
# Python データ品質ツール
PYTHONPATH=Tools/VehicleChangeDataQuality python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
# CI 補助スクリプトのテスト
ruby .github/testflight_build_publisher_test.rb
```

CI は `.github/workflows/testflight.yml`(iOS/macOS アーカイブ → TestFlight 配布)のみ。
ローカルのビルド/テスト成功を、見た目・実機・実アダプター・CloudKit 本番・CI の成功として報告しない。
署名無しビルドには CloudKit の entitlement が無い。テスト実行時と entitlement が無い時は CloudKit に触れない構成を使う。

## 製品仕様の要点(初版)

- **アカウント**: アプリ独自のログインは無い。データの持ち主は端末の iCloud アカウント。iCloud 未サインインでも全機能が端末内で動き、同期だけが「利用不可」と表示される。
- **データ**: 後方互換は持たない。DB は `Application Support/ProjectZD8/insight-v1.sqlite` の1ファイルを1接続で共有する。旧 `projectzd8.sqlite` と旧 CloudKit レコードは読まない。
- **同期**: CloudKit プライベートDBの専用ゾーンに、車両・整備記録・写真・セッションをレコード単位で `CKSyncEngine` により同期する。セッションの Raw は終了後に圧縮アーカイブ(`SessionArchive`)として1回アップロードする。デモセッションと PID 収集設定は同期しない。
- **Raw ログ**: 無応答を含む全要求を `session_samples` に1行ずつ追記する(更新禁止)。PID 定義はコード同梱(`Domain/Catalog`)で、取得時点の数式・改訂番号をセッションごとに `session_pids` へ複写する。分析は必ずこの複写で復号する。
- **デモモード**: 設定で有効にした時だけ模擬アダプターが現れ、`isDemo` 付きで記録する。
- **分析**: アプリ同梱の HTML/JavaScript ワークベンチを WebView で表示する(外部ライブラリ・ネットワーク不使用)。Swift が復号済みデータセットを渡し、対話的な集計・可視化は JavaScript が行う。
- **画面**: macOS は `NavigationSplitView`(ドライブ / ログ / 分析 / ガレージ / 整備)+ 設定シーン + メニューコマンド。iOS は `TabView`(ドライブ / ログ / ガレージ / 設定)で、整備はガレージ配下、分析はログ詳細から開く。

## アーキテクチャ

```text
Platform ──▶ Application ──▶ Domain ◀── Data
                 App/Composition が全依存を組み立てる
```

| 層 | 置くもの | 禁止 |
| --- | --- | --- |
| `App` | エントリ、`Composition/` での DI | 業務ルール・画面レイアウト |
| `Domain` | Entities / ValueObjects / Policies / Repositories(契約) / Errors / Catalog(同梱PID定義) | 他層・SwiftUI・GRDB の import |
| `Application/Features/<F>` | Actions / State / UseCases / Ports | 具象 Data アダプター・Platform・SwiftUI |
| `Data` | GRDB、CloudKit、OBD/Serial/Bluetooth、ファイル等の実装 | Platform・View |
| `Platform/{iOS,macOS}` | AppShell と Features/<F>/Views | Data・GRDB・SQL・デバイスAPIへの直接アクセス |
| `Shared` | 複数オーナーが実際に使う小さな部品のみ(`DesignSystem`) | 機能ロジック |

表に書いていない要点:
- 画面の状態と操作は Application の `@MainActor @Observable final class XxxModel`(`state` と `send(_ action:)`)が持つ。View は描画・UI一時状態・型付き Action の送出のみ。表示用の整形(時間・距離・状態ラベルのキー)も Application 側に置き、iOS/macOS で重複させない。
- iOS と macOS の画面は別ツリー・別型。ファイル全体を `#if os(iOS)` / `#if os(macOS)` で包む。共有 View 内の分岐は使わない。
- app target は `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。Domain・Data と、Application の Model 以外の型には `nonisolated` を明示する。
- リポジトリ契約は全て `async throws`。副作用(時刻・ID・永続化・通信・デバイス)はポートかクロージャで注入し、依存は Optional にしない。
- 失敗を成功や空データに潰さない。失敗は型付き enum で State に持つ(文字列キーで持たない)。「接続済み」等の表示は state の裏付けがある時だけ。
- 削除は、同期済みの行(`sync_records` に行がある)なら `deletedAt` を入れて同期に渡し、未同期なら即時に物理削除する。
- Feature 間は具象型に依存しない。横断ワークフローは所有 Feature を1つ決め、Domain 型か狭いポートで連携する。
- `Helpers` / `Utils` / `Common` / 広い `Manager` は作らない。新しい Feature やトップレベルのディレクトリは作る前にユーザーへ提案する。

## Feature 一覧(Application と Platform で同名)

| Feature | 責務 |
| --- | --- |
| `DeviceConnection` | アダプターの探索・既定アダプター・接続ポートの契約 |
| `Logging` | 接続 → 車両識別(未登録なら登録)→ セッション開始 → ポーリング → 保存 → 終了、の一連を所有する |
| `LiveTelemetry` | 記録中の最新値と直近履歴の表示状態(Logging が流すサンプルを購読するだけ) |
| `VehicleManagement` | 車両の編集・写真・削除・PID 収集設定 |
| `Maintenance` | 車両単位の整備記録・写真 |
| `LogHistory` | 記録済みセッションの一覧・詳細・削除・端末内 Raw の解放 |
| `Analysis` | 分析データセットの生成と WebView ワークベンチ |
| `Sync` | iCloud 同期の状態表示・手動同期・全データ削除 |
| `Settings` | 外観・デモモード・Raw 保持期間 |

## コード規約

- 宣言には日本語の `///` DocC を書き、メソッドには `責務:` の一文を入れる。
- 1ファイル1主要型、ファイル名=主要宣言名。命名例: `XxxUseCase`、`GRDBXxxRepository`、`CloudKitXxx`、`XxxState` / `XxxAction` / `XxxModel`。プラットフォーム固有型は `IOS` / `MacOS` 接頭辞。
- テストは本番パスをミラーする(`ProjectZD8/<path>/Foo.swift` → `ProjectZD8Tests/<path>/FooTests.swift`)。複数テストで使うテストダブルは `ProjectZD8Tests/Support/` に置く。
- UI 文字列は String Catalog (`Resources/Localization/Localizable.xcstrings`、ja/en/es)。キーは `<feature>.<画面>.<要素>` のドット区切り。
- 色・余白・角丸・書体は `Shared/DesignSystem` のトークンを使い、View に直書きしない。
- ブランド色: アクセントはシアン。オレンジは警告・ピーク用の小さな強調のみ。

## 見つけにくい場所

- DB スキーマ: `Data/Persistence/GRDB/Database/AppDatabaseMigrator.swift`(列の規約もここ)。接続は `AppDatabase`。
- 同梱 PID 定義: `Domain/Catalog/`(`OBDPIDCatalog` が入口)。数式の評価は `Domain/Policies/OBDPIDFormulaEvaluator.swift`。
- デバイス契約: `Application/Features/DeviceConnection/Ports/OBDLinkPort.swift`。実装は `Data/Devices/`。
- 同期契約: `Application/Features/Sync/Ports/CloudSyncPort.swift`。実装は `Data/Sync/`。
- 分析ワークベンチ: `Resources/AnalysisWeb/`。

## 車両変化検知の文書

`Documentation/VEHICLE_CHANGE_DETECTION_*.md` が要件・データ監査・特徴量仕様・取得/収集計画を持つ(要件の正は `..._REQUIREMENTS.md`)。オフライン品質ツールは `Tools/VehicleChangeDataQuality/`(Python 標準ライブラリのみ、製品コードに依存しない)。
文書内の「Prompt A〜F」は段階名(A=実ログ監査、B=特徴量/スコア仕様、C=macOS MLX feasibility spike、D=回顧的モデル評価、E=本番統合計画、F=統合実施)。C 以降は現在 no-go で、解除条件は `..._ACQUISITION_AND_COLLECTION_PLAN.md` §9。
