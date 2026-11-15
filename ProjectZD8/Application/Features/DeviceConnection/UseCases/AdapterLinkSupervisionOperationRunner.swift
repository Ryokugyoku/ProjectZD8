/// 常駐リンク監視の非同期の作用(初期化・車両確認・待機・VIN読取)を世代管理付きで実行します。
///
/// `cancel()` の後に古い処理の結果が届いても `eventDidOccur` へは渡しません。
@MainActor
final class AdapterLinkSupervisionOperationRunner {
    /// 非同期の作用が完了したときに状態機械へ入力するイベントの受け口です。
    var eventDidOccur: (@MainActor (AdapterLinkSupervisionEvent) -> Void)?

    /// アダプター初期化の能力です。
    private let initialization: any AdapterLinkInitializationPort

    /// 車両確認の能力です。
    private let vehicleResponse: any VehicleResponseConfirmationPort

    /// VIN読取の能力です。
    private let vinReader: any VehicleIdentificationNumberReadingPort

    /// 自動記録設定の保存境界です。
    private let automaticRecordingPreference: any AutomaticRecordingPreferencePort

    /// 現在時刻と待機の能力です。
    private let clock: any AdapterLinkSupervisionClock

    /// 現在有効な処理の世代です。`cancel()` のたびに進めます。
    private var generation = 0

    /// 実行中の非同期処理です。
    private var task: Task<Void, Never>?

    /// 非同期の作用に使う能力を注入して生成します。
    ///
    /// 責務: 初期化・車両確認・VIN読取・自動記録設定・待機の依存関係を固定します。
    /// - Parameters:
    ///   - initialization: アダプター初期化の能力。
    ///   - vehicleResponse: 車両確認の能力。
    ///   - vinReader: VIN読取の能力。
    ///   - automaticRecordingPreference: 自動記録設定の保存境界。
    ///   - clock: 現在時刻と待機の能力。
    init(
        initialization: any AdapterLinkInitializationPort,
        vehicleResponse: any VehicleResponseConfirmationPort,
        vinReader: any VehicleIdentificationNumberReadingPort,
        automaticRecordingPreference: any AutomaticRecordingPreferencePort,
        clock: any AdapterLinkSupervisionClock
    ) {
        self.initialization = initialization
        self.vehicleResponse = vehicleResponse
        self.vinReader = vinReader
        self.automaticRecordingPreference = automaticRecordingPreference
        self.clock = clock
    }

    /// 進行中の処理を取り消し、後から届く結果を無効にします。
    ///
    /// 責務: 世代を進めて実行中のタスクをキャンセルします。
    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    /// アダプター初期化を実行します。
    ///
    /// 責務: 初期化の成功を判定結果付きのイベントへ、失敗を初期化失敗のイベントへ変換します。
    func initializeAdapter() {
        launch { [initialization] in
            do {
                return .adapterInitializationSucceeded(try await initialization.initializeAdapter())
            } catch {
                return .adapterInitializationFailed
            }
        }
    }

    /// 指定したタイムアウトで車両確認を実行します。
    ///
    /// 責務: 確認の完了を応答有無付きのイベントへ、失敗を確認失敗のイベントへ変換します。
    /// - Parameter timeout: 通常のタイムアウトかアダプター側の最大タイムアウトか。
    func confirmVehicle(timeout: VehicleResponseTimeout) {
        launch { [vehicleResponse] in
            do {
                return .vehicleConfirmationCompleted(try await vehicleResponse.confirmVehicleResponse(timeout: timeout))
            } catch {
                return .vehicleConfirmationFailed
            }
        }
    }

    /// 指定した時間だけ待ってから再確認を促します。
    ///
    /// 責務: 注入された待機の完了を再確認間隔の経過イベントへ変換し、キャンセル時は何も入力しません。
    /// - Parameter duration: 待機する時間。
    func scheduleVehicleConfirmation(after duration: Duration) {
        launch { [clock] in
            do {
                try await clock.sleep(for: duration)
                return .vehicleConfirmationIntervalElapsed
            } catch {
                return nil
            }
        }
    }

    /// VINを読み取り、検知時点の自動記録設定と合わせて返します。
    ///
    /// 責務: VIN読取の完了・失敗を、その時点で読み込んだ自動記録設定付きのイベントへ変換します。
    func readVIN() {
        launch { [vinReader, automaticRecordingPreference] in
            do {
                let vin = try await vinReader.readVehicleIdentificationNumber()
                return .vinReadCompleted(vin: vin, isAutomaticRecordingEnabled: automaticRecordingPreference.load())
            } catch {
                return .vinReadFailed(isAutomaticRecordingEnabled: automaticRecordingPreference.load())
            }
        }
    }

    /// 1件の非同期処理を現在の世代で開始します。
    ///
    /// 責務: 処理の結果イベントを、世代が変わっておらずキャンセルされていない場合だけ受け口へ渡します。
    /// - Parameter operation: 結果イベントを返す処理。何も入力しない場合は `nil` を返します。
    private func launch(_ operation: @escaping @MainActor () async -> AdapterLinkSupervisionEvent?) {
        let launchedGeneration = generation
        task?.cancel()
        task = Task { [weak self] in
            let event = await operation()
            guard let self, !Task.isCancelled, launchedGeneration == generation, let event else {
                return
            }
            eventDidOccur?(event)
        }
    }
}
