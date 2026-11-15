# App Review 向け: bluetooth-central の利用理由(下書き)

App Store Connect の「App Review に関する情報 > メモ」に貼る文章の下書きです。日本語と英語は同じ内容です。
提出前に、提出するビルドの動作と一致していることを確認します。

- 状態: 下書き。実機での確認(`BACKGROUND_RECORDING_DEVICE_TEST_PROCEDURE.md`)が終わるまで確定しません。
- 書いてよいのは、アプリが実際に行うことだけです。予定している機能、確認していない動作は書きません。
- `[ ]` の箇所は、提出時に記入します。

## 日本語

### bluetooth-central を使う理由

RevTorque Insight は、車両の OBD-II ポートに挿した Bluetooth Low Energy のアダプターから車両のデータを読み取り、
走行の記録として保存するアプリです。記録は走行中ずっと続き、そのあいだユーザーは iPhone を操作しません
(運転中は画面を見ず、iPhone はロックされているか、ナビゲーションなど別のアプリが前面にあります)。
そのため、アプリがバックグラウンドにある間もアダプターとの通信を続ける必要があります。

アプリがバックグラウンドで Bluetooth を使って行うことは、次の3つです。

1. ユーザーが登録したアダプター1台への接続を待つ。
   ユーザーが設定で選んだアダプターに対して接続要求を出したままにし、車両の電源が入って
   アダプターが起動したときに接続します。周囲の機器を探し続けることはしません。
   アダプターをまだ特定できていない場合に限り、OBD アダプターが使うシリアル通信のサービスを指定して探します。
2. 接続したアダプターを通じて、車両が応答するかを確認し、車両の識別番号(VIN)を読み取る。
   車両が応答したら、ユーザーの設定に従って、通知(「車両を検知しました」と［記録開始］のボタン)を出すか、
   記録を自動で始めます。どちらにするかは、ユーザーが初回に選び、設定でいつでも変更できます。
3. 記録中、アダプターへ OBD-II の要求(車速、エンジン回転数、スロットル開度など)を送り、
   応答を端末内に保存する。
   通信が途切れた場合は接続をやり直し、3分以内に戻らなければ記録を終了します。

システムがバックグラウンドのアプリを終了した場合に備えて、Core Bluetooth の状態の保存と復元を使っています。
登録したアダプターが再び接続されたときにアプリが起動し直され、上の1から3を続けます。

### ユーザーに見える形

- 記録中は Live Activity(ロック画面と Dynamic Island)に、車両名、状態、車速、回転数、経過時間を表示します。
  Live Activity の［切断］で、アプリを開かずに記録を終了できます。
- 車両を検知したとき、または記録を自動で始めたときは、通知で知らせます。
- ユーザーが［切断］を押すと記録は終了し、同じ接続のあいだは自動で再開しません。
- ユーザーがアプリスイッチャーでアプリを終了すると、車両の検知も記録も止まります。
  車両の自動検知が止まることは、設定画面に表示しています。

### 行わないこと

- 登録していない機器への接続、周囲の Bluetooth 機器の収集は行いません。
- Bluetooth を位置の推定や追跡に使いません。アプリは位置情報を取得しません。
- 記録中でも、車両の検知を待っている間でもないときに、バックグラウンドで Bluetooth 通信を行いません。
- アプリは Bluetooth のペリフェラルとして動作しません(bluetooth-peripheral は使いません)。

### データの扱い

読み取った車両のデータは端末内に保存します。ユーザーが有効にした場合は、ユーザー自身の iCloud
(CloudKit のプライベートデータベース)にも保存します。開発者のサーバーへは送信しません。

### 審査での確認方法

この機能の確認には、OBD-II の Bluetooth Low Energy アダプターと車両が必要です。

- 対応するアダプター: [ 機種名を記入 ]
- 手元にアダプターと車両が無い場合のために、動作を収録した動画を用意しています: [ 動画の URL を記入 ]
- 動画の内容: [ 収録した手順を記入。例: アプリをバックグラウンドにして車両の電源を入れる、通知が届く、
  ［記録開始］を押す、iPhone をロックして走行する、Live Activity の［切断］で終了する ]
- サインインに使う審査用アカウント: [ 記入 ]

## English

### Why the app uses bluetooth-central

RevTorque Insight reads vehicle data from a Bluetooth Low Energy adapter plugged into the vehicle's OBD-II port and
saves it as a drive log. Logging continues for the whole drive, and the user does not operate the iPhone during
that time: the driver is not looking at the screen, and the iPhone is either locked or showing another app such as
navigation. The app therefore needs to keep communicating with the adapter while it is in the background.

In the background, the app uses Bluetooth for these three things only:

1. Waiting for a connection to the one adapter the user has registered.
   The app keeps a pending connection request to the adapter the user selected in Settings, and connects when the
   vehicle is switched on and the adapter powers up. It does not keep scanning for nearby devices. Only when the
   adapter has not been identified yet does it scan, limited to the serial-communication services used by OBD
   adapters.
2. Checking through the connected adapter whether the vehicle responds, and reading the vehicle identification
   number (VIN).
   When the vehicle responds, the app either posts a notification ("Vehicle Detected" with a "Start Recording"
   button) or starts recording automatically, depending on the user's setting. The user makes this choice on first
   use and can change it in Settings at any time.
3. While recording, sending OBD-II requests (vehicle speed, engine speed, throttle position, and similar) to the
   adapter and saving the responses on the device.
   If communication is interrupted, the app retries the connection, and ends the recording if it does not come
   back within three minutes.

The app uses Core Bluetooth state preservation and restoration in case the system terminates it in the
background. When the registered adapter connects again, the app is relaunched and continues with items 1 to 3
above.

### What the user sees

- While recording, a Live Activity (Lock Screen and Dynamic Island) shows the vehicle name, status, vehicle speed,
  engine speed, and elapsed time. The "Disconnect" button on the Live Activity ends the recording without opening
  the app.
- The app posts a notification when it detects the vehicle or when it starts recording automatically.
- When the user taps "Disconnect", the recording ends and does not restart automatically during the same
  connection.
- When the user quits the app from the App Switcher, vehicle detection and recording stop. The Settings screen
  states that automatic vehicle detection stops.

### What the app does not do

- It does not connect to devices the user has not registered, and it does not collect information about nearby
  Bluetooth devices.
- It does not use Bluetooth to estimate or track location. The app does not access location data.
- It does not communicate over Bluetooth in the background unless it is recording or waiting to detect the
  vehicle.
- It does not act as a Bluetooth peripheral (bluetooth-peripheral is not used).

### Data handling

Vehicle data read by the app is stored on the device. If the user turns it on, the data is also stored in the
user's own iCloud (CloudKit private database). Nothing is sent to the developer's servers.

### How to verify during review

Verifying this feature requires an OBD-II Bluetooth Low Energy adapter and a vehicle.

- Supported adapter: [ model name ]
- A video of the feature in use is available in case an adapter and a vehicle are not at hand: [ video URL ]
- What the video shows: [ recorded steps, for example: put the app in the background and switch the vehicle on,
  the notification arrives, tap "Start Recording", lock the iPhone and drive, end with "Disconnect" on the Live
  Activity ]
- Review account for sign-in: [ fill in ]

## 提出前に確認すること

- 上の文章の各文が、提出するビルドの動作と一致している。特に次の点。
  - 通知とボタンの英語の文言(`Localizable.xcstrings` の `vehicle-detection-detected-title`、
    `vehicle-detection-start-recording-action`、Live Activity の［切断］)が、本文の引用と一致している。
  - 「開発者のサーバーへは送信しません」が、提出するビルドの通信先と一致している。
  - 「位置情報を取得しません」が、提出するビルドの権限と一致している。
- `UIBackgroundModes` には bluetooth-central のほかに external-accessory と processing があります。
  この文書は bluetooth-central だけを説明しています。ほかの2つを尋ねられた場合の説明は別に用意します。
- `NSBluetoothAlwaysUsageDescription` の文言と矛盾していない。
