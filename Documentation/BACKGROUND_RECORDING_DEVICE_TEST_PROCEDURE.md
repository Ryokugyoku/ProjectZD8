# バックグラウンド記録の実機テスト手順書

常駐 BLE リンク、車両検知、自動記録、Live Activity、取得の回復と猶予、セッション外の後処理を、
実機(iPhone)と実アダプターと実車で確認するための手順書です。

ここに書いた合格条件は、単体テストやシミュレーターでは確認できません。ローカルのビルドやテストが
成功していても、この手順書の項目を合格として扱いません。ある項目の合格は、他の項目の合格の証拠に
なりません。

## 0. 記入欄

| 項目 | 記入 |
| --- | --- |
| 実施日 | |
| 実施者 | |
| アプリのビルド(バージョン、ビルド番号、コミット) | |
| iPhone の機種と iOS バージョン | |
| アダプター A の機種名(駐車中にスリープするもの) | |
| アダプター A のファームウェア | |
| アダプター B の機種名(駐車中にスリープしないもの) | |
| アダプター B のファームウェア | |
| 車両(型式。VIN は書かない) | |

対象アダプターの機種は未確定です。機種名は実施時に記入します。スリープする・しないの区別は、
メーカーの仕様ではなく、項目11の観察結果で決めます。

## 1. 安全と個人情報

- 走行が必要な項目は、運転者と操作者を分けます。運転者は iPhone を操作しません。
- VIN、Bluetooth アドレス、Apple アカウントの識別子、Raw 応答を、公開の Issue や PR に貼りません。
  証拠は手元に保存します。
- アプリのログには VIN、アカウント識別子、Raw の中身を出しません。ただし車両検知の通知の本文には
  VIN が表示されます。通知を含むスクリーンショットや画面収録は、共有する前に VIN を隠します。
- ログに VIN、アカウント識別子、Raw の中身が出ているのを見つけたら、その項目は不合格とし、
  該当する行を記録します。

## 2. 準備

1. iPhone にテスト対象のビルドを入れ、Apple アカウントでサインインします。
2. アダプターを既定のアダプターとして登録し、車両を1台登録します(項目9だけは未登録の車両を使います)。
3. 通知と Live Activity を許可します。
4. iPhone を Mac に接続し、Console.app で iPhone を選びます。
   - ［操作］メニューで「情報メッセージを含める」と「デバッグメッセージを含める」を有効にします。
   - 検索欄で `subsystem:Ryokugyoku.ProjectZD8` に絞り込みます。category は各項目に書いたものを
     追加で指定します(例: `category:Acquisition`)。
5. 各項目の開始時刻と終了時刻を控えます。ログの保存は、その時間帯を選択して書き出します。

Mac を車内に持ち込めない場合は、テスト後に iPhone を接続し、次のコマンドで時間帯を指定して
ログを集めます。

```sh
sudo log collect --device --start '2026-01-01 10:00:00' --output ~/Desktop/revtorque-device.logarchive
```

## 3. ログの見方

subsystem はすべてアプリの bundle ID(`Ryokugyoku.ProjectZD8`)です。

| category | 内容 | 主なメッセージ |
| --- | --- | --- |
| `BLELink` | 常駐リンクの状態 | `BLELink <前> -> <後>`、`BLELink restored peripherals count=<n>`、`BLELink adopting restored peripheral state=<状態>` |
| `VehicleDetectionNotification` | 車両検知の通知の失敗 | `Vehicle detection notification skipped: not authorized`、`Vehicle detection notification failed: …` |
| `VehicleRecording` | 記録開始を断った理由、車両照合の失敗 | `Recording start declined because another session is active`、`Registered vehicle lookup failed: …` |
| `Acquisition` | 取得ループの状態遷移 | `Acquisition started`、`Acquisition phase: acquiring`、`Acquisition phase: recovering cause=<原因> stage=<段階> attempt=<回>`、`Acquisition phase: paused cause=<原因>`、`Acquisition ended: stopped`、`Acquisition ended: gracePeriodExpired cause=<原因>`、`Acquisition ended: recordingFailed` |
| `LiveActivity` | Live Activity の状態遷移 | `Live Activity started`、`Live Activity ended`、`Live Activity closed by system`、`Live Activity stop requested: accepted`、`Live Activity stop requested: declined` |
| `RecordingSessionActivity` | Live Activity の操作の失敗 | `Session activity <操作> failed: …` |
| `PostSessionProcessing` | セッション外の後処理 | `Post-session processing scheduled`、`Post-session processing started`、`Post-session processing deferred: recording active`、`Post-session processing step <upload\|eviction> succeeded`、`Post-session processing interrupted: expired`、`Post-session processing finished: completed` |

- `BLELink` の状態は `idle`、`awaitingPeripheral`、`connecting`、`discovering`、`ready`、
  `disconnected(<理由>)` です。
- `<原因>` は `responseStall`(車両が応答しない)か `linkLost`(リンクが切れた)です。
- `<段階>` は `promptResync`、`reinitializeFromReset`、`reconnectLink` の順に進みます。

## 4. 共通の証拠

各項目で、次のものを残します。項目ごとの「残す証拠」には、これに加えるものを書いています。

- 開始時刻と終了時刻。
- その時間帯の Console.app の書き出し(または `.logarchive`)。
- 接続履歴の画面のスクリーンショット(セッションの開始時刻、終了時刻、終了の理由が分かるもの)。
- 結果(合格・不合格・未実施)と、不合格の場合は期待と違った点。

## 5. テスト項目

### 項目1: バックグラウンドでの継続

手順

1. アプリを前面にして記録を始め、ホームに受信件数が増えていくことを確認します。
2. ホーム画面へ戻り(アプリをバックグラウンドにし)、別のアプリを前面にして15分以上走行します。
3. アプリを前面に戻します。

合格条件

- バックグラウンドにしていた間も受信件数が増え続け、接続履歴では1件のセッションのままである。
- その間に `Acquisition ended:` が出ていない。
- 接続履歴のセッションの記録件数が、バックグラウンドにする前より増えている。

Console.app

- `category:Acquisition`: 開始時に `Acquisition started` と `Acquisition phase: acquiring`。
  バックグラウンドの間は `Acquisition ended:` が無い。
- `category:BLELink`: `ready` から他の状態への遷移が無い。

残す証拠

- バックグラウンドにした時刻と戻した時刻。
- 戻した直後のホーム(受信件数)と接続履歴のスクリーンショット。

### 項目2: ロック中の継続

手順

1. 記録を始めます。
2. iPhone をロックし、15分以上走行します。途中で画面を点けません。
3. ロックを解除してアプリを前面に戻します。

合格条件

- ロックしていた間も記録が続き、接続履歴では1件のセッションのままである。
- ロック画面の Live Activity の受信件数と経過時間が進んでいる(記録を前面で始めた場合)。
- その間に `Acquisition ended:` が出ていない。

Console.app

- `category:Acquisition`: ロック中に `Acquisition ended:` が無い。一時的な
  `Acquisition phase: recovering` が出た場合は、その後に `Acquisition phase: acquiring` へ戻っている。
- `category:BLELink`: `ready` から他の状態への遷移が無い。

残す証拠

- ロックした時刻と解除した時刻。
- ロック画面の Live Activity のスクリーンショット(ロック直後と解除直前)。

### 項目3: メモリ不足による終了からの状態復元

システムがアプリを終了した後に、アダプターの接続をきっかけにアプリが起動し直されることを確認します。
アプリスイッチャーでの終了(項目10)とは別の確認です。

手順

1. アダプターの電源が切れた状態(車両の電源オフ、またはアダプターを抜いた状態)で、アプリを一度起動し、
   `category:BLELink` に `BLELink start target=` が出ることを確認してから、ホーム画面へ戻ります。
2. メモリを多く使うアプリ(カメラでの動画撮影、ゲーム、地図など)を複数起動し、
   アプリがシステムに終了されるまで続けます。Console.app でアプリのプロセスが消えたこと
   (アプリのログが止まり、再度前面に出すと起動画面から始まる状態)を確認します。
   このとき、アプリスイッチャーでアプリを上へスワイプしません。
3. アプリを開かないまま、車両の電源を入れてアダプターを起動します。
4. 通知(自動記録がオフなら「車両を検知しました」、オンなら「記録を開始しました」)を待ちます。

合格条件

- アプリを開かないまま、手順4の通知が届く。
- `BLELink restored peripherals count=` が出て、その後に `ready` へ到達する。

Console.app

- `category:BLELink`: `BLELink restored peripherals count=<1以上>`、
  `BLELink adopting restored peripheral state=…`、`BLELink … -> ready`。
- 自動記録がオンの場合は `category:Acquisition` に `Acquisition started`。

残す証拠

- アプリが終了されたと判断した時刻と根拠。
- 通知のスクリーンショット(VIN を隠す)。

備考

- 手順2でシステムによる終了を起こせなかった場合は、未実施と記録します。合格にしません。
- 記録の最中にシステムに終了された場合は、最後に保存した時刻から3分以内に同じ車両で取得を再開すれば
  同じセッションを続け、3分を超えると、そのセッションは最後に保存した時刻で終了します
  (終了の理由は「予期しない終了」)。これを確認した場合は、接続履歴のスクリーンショットを残します。

### 項目4: 通知の［記録開始］

手順

1. 設定の「車両検知時の記録開始」で「通知から開始」を選びます。
2. アプリをバックグラウンドにし、車両の電源を入れます。
3. 「車両を検知しました」の通知が届いたら、通知を長押しして［記録開始］を押します。
4. 別の回で、通知の本文をタップします(［記録開始］は押しません)。

合格条件

- 手順3: アプリが前面に出て記録が始まり、通知が消える。接続履歴に新しいセッションが1件できる。
- 手順4: 本文のタップでは記録が始まらない。
- 通知が届く前に、記録が始まっていない。

Console.app

- `category:BLELink`: `… -> ready`。
- `category:Acquisition`: 手順3の後に `Acquisition started`、`Acquisition phase: acquiring`。
  手順4では `Acquisition started` が無い。
- `category:VehicleDetectionNotification`: `skipped: not authorized` や `failed:` が無い。

残す証拠

- 通知と［記録開始］ボタンのスクリーンショット(VIN を隠す)。
- ［記録開始］を押した時刻と、セッションの開始時刻。

### 項目5: 自動記録

手順

1. 設定の「車両検知時の記録開始」で「自動で開始」を選びます。
2. アプリをバックグラウンドにして iPhone をロックし、車両の電源を入れます。
3. 何も操作せずに「記録を開始しました」の通知を待ち、5分以上走行します。

合格条件

- 操作なしで記録が始まり、「記録を開始しました」の通知が届く。
- 接続履歴に新しいセッションが1件でき、登録済みの車両に紐付いている。
- 同じ接続のあいだに、セッションが2件以上できていない。

Console.app

- `category:BLELink`: `… -> ready`。
- `category:Acquisition`: `Acquisition started`、`Acquisition phase: acquiring`。
- `category:VehicleRecording`: `Recording start requested while phase=` が無い。

残す証拠

- 通知のスクリーンショット(VIN を隠す)。
- 車両の電源を入れた時刻と、セッションの開始時刻。

備考

- 記録がバックグラウンドで始まった場合、Live Activity は次にアプリを前面にするまで表示されません。
  これは不合格ではありません。

### 項目6: Live Activity の表示と［切断］

手順

1. アプリを前面にして記録を始め、iPhone をロックします。
2. ロック画面の Live Activity で、車両名、状態、車速、回転数、スロットル、受信件数、経過時間を確認します。
   Dynamic Island のある機種では、ロックを解除して Dynamic Island の表示も確認します。
3. Live Activity の［切断］を押します。アプリは開きません。
4. アダプターの電源を入れたまま5分待ちます。

合格条件

- 手順2: 各項目が表示され、車速と回転数が実際の値に追従し、受信件数と経過時間が進む。
- 手順3: アプリを開かずに記録が終わり、Live Activity が「記録を終了しました」になってから消える。
  接続履歴のセッションの終了の理由が、ユーザーによる切断である。
- 手順4: 同じ接続のあいだは、通知も自動記録も起きない。

Console.app

- `category:LiveActivity`: `Live Activity started`、`Live Activity stop requested: accepted`、
  `Live Activity ended`。
- `category:Acquisition`: `Acquisition ended: stopped`。手順4の間に `Acquisition started` が無い。
- `category:RecordingSessionActivity`: `Session activity … failed:` が無い。

残す証拠

- ロック画面と Dynamic Island の Live Activity のスクリーンショット。
- ［切断］を押した時刻と、セッションの終了時刻。

### 項目7: 8時間経過後の継続

Live Activity はシステムが8時間で閉じます。そのあとも記録が続くことを確認します。

手順

1. アプリを前面にして記録を始め、Live Activity が出たことを確認します。
2. 車両の電源を入れたまま(または走行と停車を繰り返して)8時間を超えるまで記録を続けます。
   車両のバッテリーに注意し、必要なら充電器をつなぎます。
3. 8時間を過ぎたら、Live Activity が消えていることを確認します。アプリはまだ開きません。
4. さらに10分待ってから、アプリを前面に戻します。

合格条件

- 8時間を過ぎても記録が続き、接続履歴では1件のセッションのままである。
- 手順4で、ホームの受信件数が手順3の時点より増えている。
- アプリを前面に戻すと、Live Activity がもう一度表示される。

Console.app

- `category:LiveActivity`: 8時間前後に `Live Activity closed by system`。
  手順4の後に `Live Activity started`。
- `category:Acquisition`: 8時間前後に `Acquisition ended:` が無い。

残す証拠

- 記録の開始時刻、Live Activity が消えたのを確認した時刻、前面に戻した時刻。
- 前面に戻した後のホームと Live Activity のスクリーンショット。

### 項目8: 3分の猶予(復帰する場合と切れる場合)

取得が途切れると、回復の各段階を試し、使い切ると一時停止して3分間復帰を待ちます。

手順(復帰する場合)

1. 記録を始めます。
2. アダプターとリンクを保ったまま、車両が応答しない状態にします(イグニッションをオフにする)。
3. ホームの表示が一時停止になったら、2分以内にイグニッションをオンに戻します。

手順(切れる場合)

4. 記録を始め、手順2と同じ状態にして、4分以上待ちます。

合格条件

- 復帰する場合: 同じセッションのまま取得が再開する。接続履歴のセッションは1件で、終了していない。
- 切れる場合: 一時停止から3分を過ぎるとセッションが終了する。セッションの終了時刻は、
  最後に応答を受信した時刻である(終了を処理した時刻ではない)。終了の理由は、車両の無応答である。
- どちらの場合も、途切れている間のホームと Live Activity に「記録中」と表示されていない。

Console.app

- `category:Acquisition`(復帰する場合):
  `Acquisition phase: recovering cause=responseStall stage=promptResync attempt=1` から始まり、
  `stage=reinitializeFromReset`、`stage=reconnectLink` を経て
  `Acquisition phase: paused cause=responseStall`、復帰後に `Acquisition phase: acquiring`。
  `Acquisition ended:` は無い。
- `category:Acquisition`(切れる場合): `Acquisition phase: paused cause=responseStall` の約3分後に
  `Acquisition ended: gracePeriodExpired cause=responseStall`。

残す証拠

- イグニッションをオフにした時刻、オンに戻した時刻、`paused` と `ended` のログの時刻。
- 切れる場合の、接続履歴のセッションの終了時刻と、最後の受信時刻が分かるスクリーンショット。

備考(実機で確認して結果を記録すること)

- リンクそのものが切れた場合(アダプターを抜く、圏外へ出る)の扱いは、コードの読解では
  車両の無応答と違って見えます。常駐リンクで始めた記録では、リンクが `ready` でなくなった時点で
  監視が記録の停止を要求し、3分の猶予に入らずに終了する経路があります。
  アダプターを抜いて1分以内に挿し直した場合に、同じセッションが続いたか、別のセッションになったか、
  そのときの `category:Acquisition` と `category:BLELink` のログを記録します。
  この備考の結果は、合格・不合格とは別に報告します。

### 項目9: 未登録車両

手順

1. アプリに登録していない車両にアダプターを挿し、車両の電源を入れます。
2. 自動記録、または通知の［記録開始］で記録を始め、5分以上記録してから切断します。
3. アプリのホームと車両の画面を開きます。
4. 警告カードの［車両を登録］から車両を登録します。

合格条件

- 未登録の車両でも記録が始まり、接続履歴にセッションができる。
- Live Activity の車両名が「未登録の車両」である。
- 手順3で「未登録の車両のログがあります」の警告カードが出る。
- 手順4の登録で、車両の識別番号が引き継がれ、登録後にそのセッションが登録した車両に紐付く。
  警告カードが消える。

Console.app

- `category:Acquisition`: `Acquisition started`、`Acquisition phase: acquiring`。
- `category:VehicleRecording`: `Registered vehicle lookup failed:` が無い。
- すべての category で、VIN の文字列が出ていない。

残す証拠

- 警告カードのスクリーンショット。
- 登録の前後の、接続履歴のセッションのスクリーンショット(VIN を隠す)。

### 項目10: アプリスイッチャーで終了した後に復帰しないこと

手順

1. 設定の「車両検知時の記録開始」のカードに、
   「アプリスイッチャーでアプリを終了すると、車両の自動検知は止まります。」の案内があることを確認します。
2. 車両の電源を切り、アプリスイッチャーでアプリを上へスワイプして終了します。
3. アプリを開かないまま車両の電源を入れ、10分待ちます。
4. アプリを起動します。

合格条件

- 手順3の間、通知が届かず、記録も始まらない。アプリのログが1行も出ない。
- 手順4でアプリを起動すると、常駐リンクが再開し、車両を検知する。

Console.app

- 手順3の間: `subsystem:Ryokugyoku.ProjectZD8` のログが無い。
- 手順4の後: `category:BLELink` に `BLELink start target=`、`… -> ready`。

残す証拠

- アプリを終了した時刻、車両の電源を入れた時刻、アプリを起動した時刻。
- 手順3の時間帯のログの書き出し(空であることの証拠)。
- 手順1の案内のスクリーンショット。

### 項目11: 駐車中にスリープするアダプターとしないアダプター

アダプター A とアダプター B の両方で実施します。どちらに当たるかは、手順2の観察結果で決めます。

手順

1. 自動記録をオンにして走行し、記録が続いていることを確認します。
2. 駐車して車両の電源を切り、iPhone を持ったまま車内で10分待ちます。
   `category:BLELink` で、リンクが `ready` のままか、`disconnected(…)` になったかを観察します。
3. アプリを開かないまま、30分以上あけてから車両の電源を入れます。
4. 通知も記録も始まらなかった場合は、アプリを前面に戻します。

合格条件(スリープするアダプター: 手順2でリンクが `disconnected(…)` になった場合)

- 駐車後にセッションが終了し、接続履歴に終了時刻と終了の理由が残る。
- 手順3で、アプリを開かないままリンクが `ready` に戻り、記録が始まる
  (新しいセッション。猶予の3分以内に戻った場合は同じセッション)。

合格条件(スリープしないアダプター: 手順2でリンクが `ready` のままだった場合)

- 車両の無応答として回復の各段階と一時停止を経て、3分の猶予が切れた時点でセッションが終了する。
  セッションの終了時刻は、最後に応答を受信した時刻である。
- 手順3または手順4のあとに、記録が始まる。
- 駐車中に、応答のないまま「記録中」と表示され続けていない。

Console.app

- スリープするアダプター: `category:BLELink` に `ready -> disconnected(…peripheralDisconnected…)`、
  手順3で `… -> connecting`、`… -> discovering`、`… -> ready`。
  `category:Acquisition` に手順3のあと `Acquisition started`。
- スリープしないアダプター: `category:Acquisition` に
  `Acquisition phase: recovering cause=responseStall …`、`Acquisition phase: paused cause=responseStall`、
  `Acquisition ended: gracePeriodExpired cause=responseStall`。`category:BLELink` は `ready` のまま。

残す証拠

- アダプターごとの、手順2の観察結果(`ready` のままか、何分後に `disconnected` になったか)。
- 車両の電源を切った時刻、入れた時刻、セッションの終了時刻と次のセッションの開始時刻。
- 手順3で記録が始まったのが、アプリを開く前か後か。

備考(実機で確認して結果を記録すること)

- スリープしないアダプターでは、コードの読解では、猶予切れで終了したあともリンクが `ready` のままのため、
  次にリンクが張り直されるかアプリが前面に戻るまで、車両を検知し直さないように見えます。
  手順3でアプリを開かずに記録が始まったかどうかを、合格・不合格とは別に報告します。

### 項目12: セッション外の後処理(参考。実機未検証)

セッションの終了時に予約した後処理(クラウドへのアップロードと Raw キャッシュの整理)が、
バックグラウンドで起動することを確認します。**バックグラウンドでの後処理の起動は、実機で未検証です。**
システムが起動する時刻は決められないため、デバッガーから起動を模擬します。

手順

1. Xcode から実機でアプリを起動し、記録を始めて切断します。
2. `category:PostSessionProcessing` に `Post-session processing scheduled` が出ることを確認します。
3. アプリをバックグラウンドにし、Xcode でプロセスを一時停止して、デバッガーで次を実行してから再開します。

   ```text
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"Ryokugyoku.ProjectZD8.post-session-processing"]
   ```

4. 別の回で、記録の最中に手順3を実行します。
5. 別の回で、手順3の直後に次を実行して、期限切れを模擬します。

   ```text
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"Ryokugyoku.ProjectZD8.post-session-processing"]
   ```

6. 別の回で、設定の自動アップロードをオフにして手順1から3を行います。

合格条件

- 手順3: アップロードと整理が順に実行され、完了する。接続履歴でセッションがクラウドに保存済みになる。
- 手順4: どちらの処理も実行されず、次回へ持ち越される(再予約される)。
- 手順5: 中断され、未完了として再予約される。
- 手順6: アップロードは行われず、整理だけが実行される。

Console.app(`category:PostSessionProcessing`)

- 手順3: `Post-session processing started`、`Post-session processing step upload succeeded`、
  `Post-session processing step eviction succeeded`、`Post-session processing finished: completed`。
- 手順4: `Post-session processing deferred: recording active`、
  `Post-session processing finished: incomplete`、`Post-session processing scheduled`。
- 手順5: `Post-session processing interrupted: expired`、
  `Post-session processing finished: incomplete`、`Post-session processing scheduled`。
- 手順6: `Post-session processing step upload skipped: automatic upload off`、
  `Post-session processing step eviction succeeded`。

残す証拠

- 各手順のログの書き出し。
- 手順3と手順6の後の、接続履歴のセッションの保管状態のスクリーンショット。

## 6. 結果のまとめ

| 項目 | 結果(合格・不合格・未実施) | 証拠の保存場所 | 備考 |
| --- | --- | --- | --- |
| 1 バックグラウンドでの継続 | | | |
| 2 ロック中の継続 | | | |
| 3 メモリ不足による終了からの状態復元 | | | |
| 4 通知の［記録開始］ | | | |
| 5 自動記録 | | | |
| 6 Live Activity の表示と［切断］ | | | |
| 7 8時間経過後の継続 | | | |
| 8 3分の猶予(復帰する場合) | | | |
| 8 3分の猶予(切れる場合) | | | |
| 9 未登録車両 | | | |
| 10 アプリスイッチャーで終了した後に復帰しないこと | | | |
| 11 スリープするアダプター(機種: ) | | | |
| 11 スリープしないアダプター(機種: ) | | | |
| 12 セッション外の後処理(参考) | | | |
