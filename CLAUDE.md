# ProjectZD8 / RevTorque Insight

OBDアダプター経由で車両テレメトリを取得・記録・分析する SwiftUI アプリ(iOS + macOS、単一マルチプラットフォームtarget)。
製品名は **RevTorque Insight**。target・bundle ID・永続化パスなどの技術識別子は `ProjectZD8` のまま(改名は別途合意が必要)。

## Build / Test

- Xcode 26.4+、deployment target iOS / macOS 26.4。scheme は `ProjectZD8` のみ。
- Xcodeプロジェクトは filesystem-synchronized group。ファイル追加・移動で `project.pbxproj` の編集は不要。
- 依存パッケージ: GRDB.swift 7.x。
- テストは XCTest(`ProjectZD8Tests` unit / `ProjectZD8UITests` UI)。

```sh
# macOS ビルド・単体テスト(最初に試す最小チェック)
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' build
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' \
  test -only-testing:ProjectZD8Tests/<TestClass>
# iOS ビルド
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'generic/platform=iOS Simulator' build
# Python データ品質ツール
PYTHONPATH=Tools/VehicleChangeDataQuality python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
# CI 補助スクリプトのテスト
ruby .github/testflight_build_publisher_test.rb
```

CI は `.github/workflows/testflight.yml`(iOS/macOS アーカイブ → TestFlight 配布)のみ。

## アーキテクチャ

```text
Platform ──▶ Application ──▶ Domain ◀── Data
                 App/Composition が全依存を組み立てる
```

| 層 | 置くもの | 禁止 |
| --- | --- | --- |
| `App` | エントリ (`ProjectZD8App.swift`)、`Composition/{IOS,MacOS}ApplicationComposition.swift` で DI | 業務ルール・画面レイアウト |
| `Domain` | Entities / ValueObjects / Policies / Repositories(契約) / Errors | SwiftUI・GRDB・SwiftData・他層の import |
| `Application/Features/<F>` | Actions / State / UseCases / Ports | 具象 Data アダプター・Platform・SwiftUI |
| `Data` | GRDB 永続化、CloudKit、OBD/Serial/Bluetooth、ファイル、Keychain 等の実装 | Platform・View |
| `Platform/{iOS,macOS}` | AppShell と Features/<F>/{Views,Presentation} | Data・GRDB・SQL・デバイスAPIへの直接アクセス |
| `Shared` | 複数オーナーで実際に使う小さな部品のみ(`DesignSystem/Components`) | 機能ロジックの置き場にしない |

要点:
- **View は描画・UI一時状態・型付き Action の送出のみ**。手続き・業務状態・インフラアクセスは持たない。Presentation が Action を Application 呼び出しへ変換する。
- **iOS と macOS の画面レイアウトは別ツリー・別型**。共有 View 内の大きな `#if os()` 分岐は使わない。
- 副作用(時刻・ID・永続化・通信・デバイス)はポート経由で注入し、`App/Composition` で組み立てる。
- デバイス入力は Application の use case を通ってから永続化・表示・分析へ流す。Raw ログは派生分析結果と独立に保持する。
- 失敗(未接続・モデル不在・推論失敗など)を成功や空データに潰さない。View で「接続済み」等の主張を state の裏付けなしに出さない。
- Feature 間は具象型に依存しない。横断ワークフローは所有 Feature を1つ決め、Domain 型か狭いポート経由で連携。
- `Helpers` / `Utils` / `Common` / 広い `Manager` は作らない。新しい Feature やトップレベルのディレクトリは作る前にユーザーへ提案する。

## Feature 一覧(Application と Platform で同名)

| Feature | 責務 |
| --- | --- |
| `Authentication` | Apple アカウントサインイン、資格状態復元、アクセスゲート |
| `Settings` | アカウント単位の設定と端末間同期(接続設定は除く) |
| `DeviceConnection` | OBD アダプターの探索・接続・切断・接続設定 |
| `VehicleManagement` | 車両の識別・登録・プロフィール・画像・同期・選択 |
| `Maintenance` | 車両単位の整備記録・写真・同期 |
| `LiveTelemetry` | リアルタイム表示用の状態と操作 |
| `Logging` | 取得セッション開始・サンプル記録・終了 |
| `LogHistory` | 記録済みログの照会と表示状態 |
| `Analysis` | 記録ログに対する分析の実行と結果取得 |

## コード規約(既存コードに合わせる)

- 宣言には `///` DocC を日本語で書き、メソッドには `責務:` の一文を入れる(既存コード全体の慣習)。
- 1ファイル1主要型、ファイル名=主要宣言名。命名例: `XxxUseCase`、`GRDBXxxRepository`、`XxxState` / `XxxAction`、プラットフォーム固有型は `IOS` / `MacOS` 接頭辞。
- テストは本番パスをミラー: `ProjectZD8/Application/Features/Logging/UseCases/Foo.swift` → `ProjectZD8Tests/Application/Features/Logging/UseCases/FooTests.swift`。
- UI 文字列は String Catalog (`Resources/Localization/Localizable.xcstrings`)。
- macOS UI の寸法は `Platform/macOS/AppShell/MacOSAppShellMetrics.swift` 等の Metrics 型に集約(数値リテラルを散らさない)。ブランド色: アクセントはシアン、オレンジは警告・ピーク用の小さな強調のみ。
- ローカルのビルド/テスト成功を、見た目・実機・実アダプター・CloudKit 本番・CI の成功として報告しない。

## 主要ファイルの索引

- DB スキーマ/マイグレーション: `Data/Persistence/GRDB/Database/ProjectZD8DatabaseMigrator.swift`(PID 定義シード: `StandardOBDPIDSeed.swift`, `ZD8OBDPIDSeed.swift`)
- GRDB Record / Repository: `Data/Persistence/GRDB/{Records,Repositories}/`(`Unavailable*` は DB を準備できない時に明示的失敗を返す代替実装)
- OBD プロトコル (ELM327): `Data/Devices/OBD/`(`ELM327Command`, `ELM327PIDResponseParser`, `SerializedELMCommandChannel`)、`Demo*` はデモモード用
- トランスポート: macOS シリアル/RFCOMM は `Data/Devices/Serial/`、iOS は CoreBluetooth / ExternalAccessory (`Data/Devices/OBD/`, `Data/Devices/IOS*`)
- CloudKit 同期: `Data/Network/CloudKit/`
- 認証: `Data/Authentication/`(Keychain、Apple ID、アカウント削除)
- 取得証跡 (acquisition evidence): Domain `ConnectionSessionAcquisition*` / GRDB `ConnectionSessionAcquisition*Record`
- 画面の入口: `Platform/iOS/AppShell/IOSAppShellView.swift`, `Platform/macOS/AppShell/MacOSAppShellView.swift`

検索: `rg --files ProjectZD8 ProjectZD8Tests | rg '/<Feature>/'`、`rg -n '^## ' Documentation/*.md`。

## Documentation

| 文書 | 内容 |
| --- | --- |
| `Documentation/VEHICLE_CHANGE_DETECTION_REQUIREMENTS.md` | 車両変化検知の要件と証拠境界(要件の正) |
| `Documentation/VEHICLE_CHANGE_DETECTION_DATA_INVENTORY.md` | ログ保存・復元・結合の現状と不足 |
| `Documentation/VEHICLE_CHANGE_DETECTION_DATA_QUALITY_MEASUREMENT_PLAN.md` | 読み取り専用スナップショットの匿名化・品質測定契約 |
| `Documentation/VEHICLE_CHANGE_DETECTION_DATA_AUDIT.md` | 実機ログの匿名品質監査結果 |
| `Documentation/VEHICLE_CHANGE_DETECTION_FEATURE_SPEC.md` | 特徴量・走行状態・スコア候補と採用ゲート |
| `Documentation/VEHICLE_CHANGE_DETECTION_ACQUISITION_AND_COLLECTION_PLAN.md` | 取得時メタデータ、収集、再測定、段階実装計画 |
| `Documentation/OBDLINK_MX_PLUS_HARDWARE_ACCEPTANCE.md` | OBDLink MX+ 実機受け入れ手順 |
| `Tools/VehicleChangeDataQuality/README.md` | オフライン品質調査ツール(Python 標準ライブラリのみ、製品コードに依存しない) |
| `PRODUCT_VALUE_AND_APP_STORE_PRICING_ASSESSMENT.md` | 製品価値・価格査定 |

車両変化検知文書内の「Prompt A〜F」は段階名: A=実ログ監査、B=特徴量/スコア仕様、C=macOS MLX feasibility spike、D=回顧的モデル評価、E=本番統合計画、F=承認済み統合フェーズの実施。現状 C 以降は no-go(解除条件は ACQUISITION_AND_COLLECTION_PLAN §9)。
