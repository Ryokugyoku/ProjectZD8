# CodeMetrics(Swift の複雑さチェック)

共通ルール §5「コードの複雑さの上限」を機械的に確かめるツール。Claude Code のフック(編集のたび)と CI(PR ごと)から呼ぶ。この文書が仕様の正。

- 実行環境: Python 3.9 以上、外部依存は `lizard==1.26.1` のみ(`requirements.txt`)。
- 置き場所: `Tools/CodeMetrics/`(パッケージ `code_metrics/`、入口 `check_swift_metrics.py`、テスト `Tests/`)。
- 製品コードに依存しない。

## 1. 計測する指標と上限

| ID | 指標 | 単位 | 上限 | 計測方法 |
| --- | --- | --- | --- | --- |
| `cyclomatic` | 循環的複雑度 | 1関数 | 10 | lizard の CCN |
| `cognitive` | 認知的複雑度 | 1関数 | 15 | lizard `-Ecognitive` の CogC |
| `nesting` | 制御構造のネスト | 1関数 | 3 | 本ツール独自(§2) |
| `function_length` | 関数の行数 | 1関数 | 80 | lizard の length(宣言行から閉じ括弧まで) |
| `function_count` | 関数の数 | 1ファイル | 20 | 本ツール独自(§3) |
| `file_lines` | 物理行数 | 1ファイル | 500 | 改行の数(末尾に改行がない最終行も1行) |

値が上限と**等しい**ものは違反ではない。上限を**超えた**ものだけが違反。

lizard の NS/ND(ネスト)は Swift の `try` を入れ子として数えるため使わない。

## 2. ネストの数え方(`nesting`)

関数本体の中で、制御構造の `{` が何段重なっているかの最大値。

- 数える `{`: 直前のトークン列が次のキーワードで始まる構文の本体 — `if`、`else`(`else if` を含む)、`guard ... else`、`switch`、`for`、`while`、`repeat`、`do`、`catch`。
- `} else {` と `} catch {` は閉じた構造と同じ段に開く(段は増えない)。
- 数えない `{`: クロージャ、型・関数・プロパティの本体、`switch` の `case` ラベル(`case` は `{` を持たない)。
- `switch` の中の `if` は2段。
- 文字列リテラル(`"..."`、`"""..."""`)と、コメント(`//`、`/* */`)の中の括弧やキーワードは無視する。
- 関数の中で定義したネスト関数は、外側の関数とは別に数える(外側の段数を引き継がない)。
- 例: `for { if { while { if { } } } }` は 4。`guard let v else { return }` の後の `switch v { case 1: if v > 0 { } }` は 2。`try foo()` だけの関数は 0。

## 3. 関数の数え方(`function_count`)

lizard が返す関数のうち、宣言行(開始行)に `func`、`init`、`subscript`、`deinit` のいずれかのキーワードを含むものを数える。次は数えない。

- 計算プロパティと、その `get` / `set` / `willSet` / `didSet`
- 他の関数の中で定義したネスト関数

1ファイルの合計(すべての型・extension を合わせた数)で判定する。

## 4. ベースライン(既存の超過)

既存コードには上限を超える箇所がある。`baseline.json` に記録した超過は、**値が記録より大きくならない限り**許容する(警告として表示し、失敗にはしない)。

- キー: ファイル単位の指標は `(相対パス, 指標ID)`。関数単位の指標は `(相対パス, 関数名#同名の出現順, 指標ID)`。出現順は同じファイル内で同じ名前の関数が出てくる順に 0 から振る。
- 値: その時点の計測値。
- ベースラインにない超過、または記録値より大きい超過は**エラー**。
- 記録値より小さくなった超過は警告のまま(ベースラインは自動では更新しない)。
- 相対パスはリポジトリのルートからの `/` 区切り。
- ファイル形式は JSON。キーの順序を固定して出力し(差分が読めるように)、末尾に改行を付ける。形は `{"files": {<相対パス>: {<指標ID>: 値}}, "functions": {<相対パス>: {"<関数名>#<出現順>": {<指標ID>: 値}}}}`。置き場所は `<root>/Tools/CodeMetrics/baseline.json`。ファイルがなければ空とみなす。
- 出現順は、lizard が返すすべての関数(ネスト関数・`get`/`set` を含む)を開始行順に並べて振る。
- 通常モードではエラーも警告も標準出力へ出す。`--hook` ではエラーと警告の両方を標準エラーへ出す(§5)。
- `--changed-since` は追跡外(untracked)の新規ファイルを含まない。git が失敗した場合(不正な REF など)は理由を標準エラーに出して終了コード 1。

## 4.1 入力の安全性

引数やフック入力は AI エージェントが組み立てることがあるため、次を守る。

- **ルートの外は読まない**: 対象ファイル(FILE 引数、`--changed-since` の結果、`--hook` のパス)は、シンボリックリンクを解決した実パスがルートの実パスの配下にあるものだけを扱う。配下にないものは、存在しないファイルと同じく黙って飛ばす。
- **ベースラインはルート直下の固定パスだけ**: `<root>/Tools/CodeMetrics/baseline.json` 以外を読み書きしない。実パスがルートの外を指す場合(リンクなど)は理由を標準エラーに出して終了コード 1。
- **ルートはコマンドライン引数から受け取らない**: ルートは本ツールの置き場所から決める(`check_swift_metrics.py` の2つ上のディレクトリ = リポジトリのルート)。テスト用に限り、環境変数 `CODE_METRICS_ROOT` で上書きできる。上書き先が実在するディレクトリでなければ理由を標準エラーに出して終了コード 1。
- **`--changed-since REF`**: REF は `[A-Za-z0-9._/~^@-]` だけからなり、先頭が英数字で、長さ 1〜200 文字のものだけを受け付ける(`re.fullmatch` で確かめる)。それ以外(`-` で始まるものを含む)は git に渡さず、理由を標準エラーに出して終了コード 1。git には `git rev-parse --verify --end-of-options <REF>^{commit}` で確かめたコミットの SHA だけを渡す。git のパス引数は `--` の後に置く。

## 5. コマンド

```sh
python3 Tools/CodeMetrics/check_swift_metrics.py FILE...
python3 Tools/CodeMetrics/check_swift_metrics.py --changed-since REF
python3 Tools/CodeMetrics/check_swift_metrics.py --update-baseline
python3 Tools/CodeMetrics/check_swift_metrics.py --hook < hook.json
```

- ルート: §4.1 のとおり本ツールの置き場所から決める(`--root` オプションはない)。テストでは環境変数 `CODE_METRICS_ROOT` を使う。
- 対象ファイル: 拡張子 `.swift` のみ。存在しないファイルと `.swift` 以外は黙って飛ばす。対象が0件なら終了コード 0。
- `--changed-since REF`: `git diff --name-only --diff-filter=ACMR REF...HEAD` と、作業ツリーの未コミット変更(`git diff --name-only HEAD`)を合わせたファイルを対象にする。
- `--update-baseline`: `ProjectZD8/`、`ProjectZD8Tests/`、`ProjectZD8UITests/`、`RecordingSessionLiveActivity/` 配下の全 `.swift` を計測し、超過だけを `Tools/CodeMetrics/baseline.json` に書き出す。終了コード 0。
- `--hook`: Claude Code の PostToolUse フック用。標準入力の JSON から `tool_input.file_path`(なければ `tool_response.filePath`)を読み、そのファイルだけを確かめる。エラーか警告(ベースラインで許容中の超過)が1件でもあれば、その全行を**標準エラー**に出して終了コード **2**(Claude にフィードバックされる)。警告が1件以上ある場合は、最後に次の1行を加える: `note: 改修したファイルの既存の超過(warning)も、この変更の中で解消する(共通ルール §5)。解消したら --update-baseline でベースラインから外す。` エラーも警告もなければ何も出さず 0。JSON が読めない・パスがない場合は 0。

## 6. 出力と終了コード

- 1件1行、Xcode/GitHub が解釈できる形式: `<相対パス>:<行>: error: <指標ID> <値> > <上限> (<関数名>)`。ファイル単位の指標は行を 1、関数名を省く。ベースラインで許容したものは `warning:` とし、末尾に `[baseline <記録値>]` を付ける。
- 関数単位の行は関数の開始行。
- 出力の順序: パス順、同じパス内は行順、同じ行は指標ID順。
- 終了コード: エラーが1件以上で 1、なければ 0(警告だけなら 0)。`--hook` はエラーか警告が1件以上で 2。lizard が入っていない場合は理由を標準エラーに出して 3。

## 7. 実装上の制約

- 本ツール自身も共通ルール §5 に従う(1関数の循環的複雑度10・認知的複雑度15・ネスト3段・80行、1ファイルの関数20個・500行)。責務ごとにモジュールを分ける(例: 計測、ネスト計測、ベースライン、出力、CLI)。
- 日本語の docstring を付ける。
- 標準ライブラリと lizard 以外を使わない。
