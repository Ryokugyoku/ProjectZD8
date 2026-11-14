# ProjectZD8 / RevTorque Insight

OBDアダプター経由で車両テレメトリを取得・記録・分析する SwiftUI アプリ(iOS + macOS、単一マルチプラットフォームtarget)。製品名は **RevTorque Insight**。target・bundle ID・永続化パス等の識別子は `ProjectZD8` のまま(改名は要合意)。

## Build / Test

Xcode 26.4+(deployment target iOS/macOS 26.4)、scheme `ProjectZD8` のみ、GRDB.swift 7.x、XCTest。filesystem-synchronized group のためファイル追加・移動で `project.pbxproj` 編集は不要。

```sh
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' build
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'platform=macOS' test -only-testing:ProjectZD8Tests/<TestClass>
xcodebuild -project ProjectZD8.xcodeproj -scheme ProjectZD8 -destination 'generic/platform=iOS Simulator' build
PYTHONPATH=Tools/VehicleChangeDataQuality python3 -m unittest discover -s Tools/VehicleChangeDataQuality/Tests -v
ruby .github/testflight_build_publisher_test.rb
```

- 実行範囲: Swift は変更した型の `-only-testing:ProjectZD8Tests/<TestClass>`(複数可)、`Tools/VehicleChangeDataQuality/` は unittest 全件、`.github/` は ruby テスト。PR 説明の「テスト」欄にコマンドと結果を書く。
- CI: `tests.yml`(PR と main push。macOS 単体テスト全件 `-only-testing:ProjectZD8Tests`、UI テストは署名なしで起動不可のため対象外。Ruby・Python テストも実行。Xcode 26.6、`CODE_SIGNING_ALLOWED=NO`)、`testflight.yml`(main で手動、iOS/macOS アーカイブ→TestFlight)。
- ローカルのビルド/テスト成功を、見た目・実機・実アダプター・CloudKit 本番・CI の成功として報告しない。

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
- iOS と macOS の画面は別ツリー・別型。共有 View 内の大きな `#if os()` 分岐は禁止。
- 副作用(時刻・ID・永続化・通信・デバイス)はポート経由で注入。デバイス入力は use case 経由で永続化・表示・分析へ流し、Raw ログは派生分析結果と独立に保持。
- 失敗(未接続・モデル不在・推論失敗等)を成功や空データに潰さない。「接続済み」等の表示は state の裏付けがある時だけ。
- Feature 間は具象型に依存しない。横断ワークフローは所有 Feature を1つ決め、Domain 型か狭いポートで連携。
- `Helpers`/`Utils`/`Common`/広い `Manager` は作らない。新 Feature・トップレベルディレクトリは作る前にユーザーへ提案。

## Feature(Application と Platform で同名)

`Authentication`(Apple サインイン・資格復元・アクセスゲート) / `Settings`(アカウント設定と端末間同期、接続設定除く) / `DeviceConnection`(アダプター探索・接続・切断・接続設定) / `VehicleManagement`(車両の識別・登録・プロフィール・画像・同期・選択) / `Maintenance`(整備記録・写真・同期) / `LiveTelemetry`(リアルタイム表示) / `Logging`(取得セッション開始・記録・終了) / `LogHistory`(記録済みログ照会) / `Analysis`(記録ログの分析実行と結果)

## コード規約

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
