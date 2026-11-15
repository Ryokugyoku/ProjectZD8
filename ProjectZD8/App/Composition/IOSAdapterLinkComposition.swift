#if os(iOS)
import Foundation

/// iOSの常駐リンク監視と記録の調停役を組み立てます。
@MainActor
enum IOSAdapterLinkComposition {
    /// 常駐リンク上の具象ポートと記録制御を注入した常駐リンク監視を生成します。
    ///
    /// 責務: ELM初期化・車両確認・VIN読取・通知・自動記録設定・時計を1本の常駐リンクへ結び付け、
    /// 調停役の記録終了と手動接続のアダプター使用の開始・終了を監視の入力へ結び付けます。
    /// - Parameters:
    ///   - residentLink: プロセスに1本だけの常駐リンク一式。
    ///   - notifier: 応答処理を有効化済みの車両検知通知。
    ///   - recordingControl: 記録の開始・停止を受け取る調停役。
    /// - Returns: 未開始の常駐リンク監視。`IOSAdapterLinkSupervisionDriver.launch()` で開始します。
    static func makeSupervision(
        residentLink: IOSResidentAdapterLink,
        notifier: IOSVehicleDetectionNotifier,
        recordingControl: VehicleRecordingCoordinator
    ) -> AdapterLinkSupervisionUseCase {
        let supervision = AdapterLinkSupervisionUseCase(
            link: residentLink.link,
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: UserDefaultsDefaultAdapterPreferenceStore()
            ),
            initialization: AdapterLinkELMInitializer(stream: residentLink.stream),
            vehicleResponse: AdapterLinkVehicleResponseConfirmer(stream: residentLink.stream),
            vinReader: AdapterLinkVehicleIdentificationNumberReader(stream: residentLink.stream),
            notifications: notifier,
            automaticRecordingPreference: UserDefaultsAutomaticRecordingPreferenceStore(),
            recordingControl: recordingControl,
            clock: SystemAdapterLinkSupervisionClock()
        )
        recordingControl.supervisedRecordingDidFinish = { [weak supervision] endReason in
            supervision?.recordingDidFinish(endReason: endReason)
        }
        recordingControl.manualAdapterUseDidBegin = { [weak supervision] in
            supervision?.externalAdapterUseDidBegin()
        }
        recordingControl.manualAdapterUseDidEnd = { [weak supervision] in
            supervision?.externalAdapterUseDidEnd()
        }
        return supervision
    }

    /// 接続セッションと登録済み車両の照合を注入した記録の調停役を生成します。
    ///
    /// 責務: 記録開始の手順・VIN照合・サインイン中アカウントの取得元・統合ログへの診断記録を調停役へ結び付けます。
    /// - Parameters:
    ///   - lifecycle: 接続セッションの開始・車両関連付け・終了を保持するモデル。
    ///   - authentication: サインイン中アカウントの識別子を持つ認証モデル。
    /// - Returns: テレメトリの開始・停止の出力が未設定の調停役。`connectTelemetry(of:to:)` で設定します。
    static func makeRecordingCoordinator(
        lifecycle: ConnectionSessionLifecycleModel,
        authentication: AuthenticationSessionModel
    ) -> VehicleRecordingCoordinator {
        let findVehicle = FindRegisteredVehicleByVINUseCase(repository: CloudKitVehicleRepository())
        return VehicleRecordingCoordinator(
            startSession: StartVehicleRecordingSessionUseCase(lifecycle: lifecycle),
            findVehicle: { vin in
                try await findVehicle.execute(
                    vin: vin,
                    accountIdentifier: authentication.state.session?.userIdentifier
                )
            },
            diagnostics: OSLogVehicleRecordingDiagnosticsAdapter()
        )
    }

    /// 調停役のテレメトリ開始・停止の出力をLiveTelemetryへ結び付けます。
    ///
    /// 責務: Loggingの記録開始要求をLiveTelemetryの開始要求へ写し、停止をLiveTelemetryの停止操作へ写します。
    /// 車両ありなら登録済み車両(型式コード付き)、車両なしなら未登録車両(標準PIDのみ)として取得を始めます。
    /// - Parameters:
    ///   - coordinator: 記録の調停役。
    ///   - liveTelemetryModel: テレメトリの取得を保持するモデル。
    static func connectTelemetry(of coordinator: VehicleRecordingCoordinator, to liveTelemetryModel: LiveTelemetryModel) {
        coordinator.startTelemetry = { request in
            let vehicle: LiveTelemetryVehicleContext = request.vehicle.map {
                .registered($0.id, vehicleModelCode: request.vehicleModelCode)
            } ?? .unregistered
            liveTelemetryModel.send(
                .startRequested(request.endpoint, vehicle, adapterProbeEvidence: request.adapterProbeEvidence)
            )
        }
        coordinator.stopTelemetry = { liveTelemetryModel.send(.stopRequested) }
    }
}
#endif
