import Foundation

/// PID継続取得の状態変化と前面復帰を受け、記録中の常時表示(Live Activity)を開始・更新・終了します。
///
/// - 開始はアプリが前面の時だけです。バックグラウンドで始まった記録は次の前面復帰で表示します。
/// - システムに表示を閉じられても(8時間上限等)記録は止めず、次の前面復帰で表示し直します。
/// - 取得が待機(`idle`)か失敗(`failed`)へ移ったら最終内容を出して閉じ、表示用の車両写真を消します。
/// - 表示・写真の失敗はすべて診断へ残し、記録処理へは波及させません。
/// - 表示への操作は受け付けた順に1件ずつ実行します(終了が更新を追い越さないため)。写真の保存・削除は即時に行います。
/// - 開始の最中にセッションが終わったら、開始の完了後に直ちに閉じます。終わったセッションの開始・更新は次のセッションの表示を
///   上書きしません(直列化と世代は `RecordingSessionActivityOperationSequencer` が持ちます)。
@MainActor
final class RecordingSessionActivityUseCase {
    /// 常時表示の境界です。
    private let activity: any SessionActivityPort
    /// 境界への操作の直列化と、セッションの世代による古い操作の破棄です。
    private let operations: RecordingSessionActivityOperationSequencer
    /// 表示用の車両写真を置く境界です。
    private let photos: any SessionActivityVehiclePhotoPort
    /// 失敗を残す診断記録です。
    private let diagnostics: any RecordingSessionActivityDiagnosticsPort
    /// 表示の開始・終了を残す診断記録です。未設定なら記録しません。
    private let lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)?
    /// 現在時刻を返す処理です。
    private let now: @MainActor () -> Date
    /// アプリがいま前面(操作可能)かどうかを返す処理です。
    private let isForeground: @MainActor () -> Bool
    /// 登録済み車両のプロフィールを返す処理です。見つからなければ `nil` を返します。
    private let vehicleProfile: @MainActor (VehicleID) -> VehicleProfile?
    /// 表示更新の間引きです。セッションごとに作り直します。
    private var throttle = RecordingSessionActivityUpdateThrottle()
    /// 直近に受け取った取得状態です。
    private var telemetry = LiveTelemetryState()
    /// 記録中のセッションの表示情報です。記録中でなければ `nil` です。
    private var session: RecordingSessionActivitySession?

    /// 境界・時刻・前面状態・車両の参照先を固定して生成します。
    ///
    /// 責務: 常時表示の制御に必要な副作用をすべて注入で受け取ります。
    /// - Parameters:
    ///   - activity: 常時表示の境界。
    ///   - photos: 表示用の車両写真を置く境界。
    ///   - diagnostics: 失敗を残す診断記録。
    ///   - now: 現在時刻を返す処理。
    ///   - isForeground: アプリがいま前面かどうかを返す処理。
    ///   - vehicleProfile: 登録済み車両のプロフィールを返す処理。
    ///   - lifecycleDiagnostics: 表示の開始・終了を残す診断記録。
    init(
        activity: any SessionActivityPort,
        photos: any SessionActivityVehiclePhotoPort,
        diagnostics: any RecordingSessionActivityDiagnosticsPort,
        now: @escaping @MainActor () -> Date = { Date() },
        isForeground: @escaping @MainActor () -> Bool,
        vehicleProfile: @escaping @MainActor (VehicleID) -> VehicleProfile?,
        lifecycleDiagnostics: (any RecordingSessionActivityLifecycleDiagnosticsPort)? = nil
    ) {
        self.activity = activity
        operations = RecordingSessionActivityOperationSequencer(activity: activity, diagnostics: diagnostics)
        self.photos = photos
        self.diagnostics = diagnostics
        self.now = now
        self.isForeground = isForeground
        self.vehicleProfile = vehicleProfile
        self.lifecycleDiagnostics = lifecycleDiagnostics
    }

    /// 境界へ受け付けた操作がすべて終わるまで待ちます。
    ///
    /// 責務: 呼び出し時点までに受け付けた開始・更新・終了の完了を待てるようにします。
    func waitForPendingOperations() async {
        await operations.waitForPendingOperations()
    }

    /// PID継続取得の状態変化を表示へ反映します。
    ///
    /// 責務: 記録の開始・継続・終了を判定し、表示の開始(前面時のみ)・間引いた更新・最終内容での終了へ変換します。
    /// - Parameter state: PID継続取得の最新状態。
    func telemetryStateDidChange(_ state: LiveTelemetryState) {
        telemetry = state
        guard state.isConnectionActive else {
            finishSessionIfNeeded()
            return
        }
        if session == nil {
            beginSession()
            return
        }
        refreshVehicleIfNeeded()
        guard activity.isPresenting, let content = makeContent(), let generation = operations.currentGeneration else { return }
        guard throttle.admit(content, at: now()) else { return }
        operations.enqueueUpdate(content, generation: generation)
    }

    /// アプリが前面へ戻ったことを表示へ反映します。
    ///
    /// 責務: 記録中で表示が出ていなければ表示を開始します。出ていれば何もしません(二重開始の防止)。
    func appDidEnterForeground() {
        guard session != nil, !activity.isPresenting else { return }
        startPresentation()
    }

    /// 新しい記録セッションの表示情報を作り、前面なら表示を開始します。
    ///
    /// 責務: 開始時刻・車両・写真を確定し、世代と間引きを初期化して、前面の時だけ表示開始を受け付けます。
    private func beginSession() {
        session = RecordingSessionActivitySession(startedAt: now())
        operations.beginSession()
        throttle = RecordingSessionActivityUpdateThrottle()
        refreshVehicleIfNeeded()
        guard isForeground() else { return }
        startPresentation()
    }

    /// 現在の内容で表示開始を受け付けます。
    ///
    /// 責務: 開始する内容を送信済みとして間引きへ記録し、実行時点でこのセッションが続いていて表示が出ていなければ開始して、
    /// 開始できたことを診断へ残します。
    private func startPresentation() {
        guard let content = makeContent(), let generation = operations.currentGeneration else { return }
        throttle = RecordingSessionActivityUpdateThrottle()
        _ = throttle.admit(content, at: now())
        let lifecycleDiagnostics = lifecycleDiagnostics
        operations.enqueueStart(content, generation: generation) {
            lifecycleDiagnostics?.activityStarted()
        }
    }

    /// 記録中のセッションがあれば、最終内容を出して表示を閉じ、表示用写真を消します。
    ///
    /// 責務: セッションの終わりを1回だけ世代の終わり・表示の終了・写真の削除へ変換します。終了は先に受け付けた開始の完了後に実行し、
    /// その時点で表示が出ていなければ送りません。終了できたことを診断へ残します。
    private func finishSessionIfNeeded() {
        guard session != nil, let finalContent = makeContent() else { return }
        session = nil
        operations.endSession()
        let lifecycleDiagnostics = lifecycleDiagnostics
        operations.enqueueEnd(finalContent) {
            lifecycleDiagnostics?.activityEnded()
        }
        removePhotos()
    }

    /// 取得中の車両が変わっていれば、表示用の写真を置き換えます。
    ///
    /// 責務: 車両IDの変化を写真の保存(写真がある登録済み車両)または削除へ変換します。保存の失敗は写真なしで続けます。
    private func refreshVehicleIfNeeded() {
        guard var current = session else { return }
        let vehicleID = telemetry.vehicle?.vehicleID
        guard !current.hasResolvedVehicle || current.vehicleID != vehicleID else { return }
        current.hasResolvedVehicle = true
        current.vehicleID = vehicleID
        current.photoFileName = storePhoto(for: vehicleID)
        session = current
    }

    /// 車両の写真を表示用に保存します。
    ///
    /// 責務: 写真がある登録済み車両なら保存してファイル名を返し、無ければ古い写真を消します。失敗は診断へ残して `nil` を返します。
    /// - Parameter vehicleID: 取得中の車両ID。未登録なら `nil`。
    /// - Returns: 表示用写真のファイル名。写真なしなら `nil`。
    private func storePhoto(for vehicleID: VehicleID?) -> String? {
        guard let vehicleID, let photoData = vehicleProfile(vehicleID)?.photoData else {
            removePhotos()
            return nil
        }
        do {
            return try photos.replacePhoto(with: photoData, for: vehicleID)
        } catch {
            diagnostics.operationFailed(.storePhoto, error: error)
            return nil
        }
    }

    /// 表示用写真をすべて消します。
    ///
    /// 責務: 写真の削除を実行し、失敗を診断へ残します。直後に保存する写真を消さないよう、操作の列へは並べず即時に行います。
    private func removePhotos() {
        do {
            try photos.removeAllPhotos()
        } catch {
            diagnostics.operationFailed(.removePhotos, error: error)
        }
    }

    /// 現在の取得状態とセッション情報から表示内容を作ります。
    ///
    /// 責務: 車両名を引き、純粋型の表示内容へ変換します。
    /// - Returns: 表示内容。セッションが無ければ `nil`。
    private func makeContent() -> RecordingSessionActivityContent? {
        guard let session else { return nil }
        return RecordingSessionActivityContent(
            telemetry: telemetry,
            vehicleName: session.vehicleID.flatMap { vehicleProfile($0)?.name },
            startedAt: session.startedAt,
            vehiclePhotoFileName: session.photoFileName
        )
    }
}
