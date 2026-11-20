# 段階的なモジュール化 計画

アプリ本体(単一ターゲット `ProjectZD8`)から、業務のまとまり(コンテキスト)ごとにローカル Swift Package のモジュールへ、改修のたびに少しずつ移す。進め方のルールは `CLAUDE.md`「段階的なモジュール化」。この文書は対応表・順番・状態の正とする。

## 状態の意味

| 状態 | 意味 |
| --- | --- |
| 未着手 | 型を移さない。改修はアプリ本体のまま行う |
| 移行中 | 改修で触った型を、その PR で一緒にモジュールへ移す |
| 移行済み | 型はすべてモジュールにある。アプリ本体に新しく作らない |

## 準備(一度だけ)

| 手順 | 内容 | 状態 |
| --- | --- | --- |
| 0-1 | `Packages/` にローカル Swift Package を作り、アプリ本体とテストターゲットから参照する。同じ PR で、複雑さチェックの走査対象(`Tools/CodeMetrics/` の `BASELINE_SCAN_DIRS`)と CI のテスト範囲(`tests.yml`)に `Packages/` を加える | 未着手 |
| 0-2 | アーキテクチャテストを追加する(層の import 禁止、移行済みコンテキストの型をアプリ本体に作らない) | 未着手 |
| 0-3 | `Domain/` をまるごと `ZD8Domain` モジュールへ移す(共有カーネル) | 未着手 |

0-3 が終わるまで、下のコンテキストは「未着手」のままにする。

## コンテキストと移す順番

| 順 | モジュール | 含む Feature | 状態 | 移す前の条件 |
| --- | --- | --- | --- | --- |
| 1 | `ZD8Account` | Authentication, Settings | 未着手 | 準備の完了 |
| 2 | `ZD8Vehicle` | VehicleManagement, Maintenance | 未着手 | 準備の完了 |
| 3 | `ZD8SessionReview` | LogHistory, Analysis | 未着手 | 準備の完了 |
| 4 | `ZD8Acquisition` | DeviceConnection, Logging, LiveTelemetry | 未着手 | 取得ワークフローの所有 Feature(Logging か LiveTelemetry)を決め、両者の相互参照を一方向にする |
| 5 | `ZD8RoadRegulation` | RoadRegulation | 未着手 | 準備の完了 |

- 各モジュールに置くのは、その Feature の `Application/Features/<F>/` 配下(Actions / State / UseCases / Ports)と、そのコンテキストだけが使うリポジトリの契約。
- アプリ本体に残すもの: `Data/`(GRDB・CloudKit・デバイス。DB は1つのまま)、`Platform/`、`App/`、`Shared/`。

## 既知の課題

- Logging と LiveTelemetry が互いのポート・入力型を参照している(2026-11-16 時点で Logging → LiveTelemetry 約10型)。`ZD8Acquisition` に着手する前に解消する。
- 残りが少なくなったコンテキストは、改修を待たずにまとめて移す PR を1本出してよい。
