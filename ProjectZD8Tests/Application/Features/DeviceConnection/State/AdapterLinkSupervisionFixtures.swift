import Foundation
@testable import ProjectZD8

/// 常駐リンク監視のテストで共通に使う既定アダプター設定・判定結果・状態・条件の組です。
@MainActor
enum AdapterLinkSupervisionFixtures {
    /// テストの基準時刻です。
    nonisolated static let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 仕様の確認窓(10分)の秒数です。
    static let windowSeconds: TimeInterval = 600

    /// 仕様の確認と確認の最短間隔(1秒)の秒数です(U3 受け入れ条件 3)。
    static let intervalSeconds: TimeInterval = 1

    /// 仕様の1窓あたりの確認回数の上限です(最初の確認を含む。窓 ÷ 最短間隔 = 600。U3 受け入れ条件 4)。
    static let maximumAttempts = 600

    /// 仕様の抑止中の見張りの上限(8時間)の秒数です(U3 受け入れ条件 11)。
    static let heldWatchSeconds: TimeInterval = 8 * 60 * 60

    /// 稼働条件を満たす既定のBLEアダプター設定です。
    static let blePreference = DefaultAdapterPreference(
        adapterID: "ble-a",
        transportMode: .bluetooth,
        connectionTransport: .bluetoothLowEnergy,
        displayName: "Adapter A",
        systemIdentifier: "6F1D2C3B-0000-4000-8000-00000000000A"
    )

    /// 切替先の別のBLEアダプター設定です。
    static let otherBLEPreference = DefaultAdapterPreference(
        adapterID: "ble-b",
        transportMode: .bluetooth,
        connectionTransport: .bluetoothLowEnergy,
        displayName: "Adapter B",
        systemIdentifier: "6F1D2C3B-0000-4000-8000-00000000000B"
    )

    /// 稼働条件を満たさないBluetooth Classicのアダプター設定です。
    static let classicPreference = DefaultAdapterPreference(
        adapterID: "classic",
        transportMode: .bluetooth,
        connectionTransport: .bluetoothClassic,
        displayName: "Classic Adapter",
        systemIdentifier: "classic-system-id"
    )

    /// 稼働条件を満たさないシリアルのアダプター設定です。
    static let serialPreference = DefaultAdapterPreference(
        adapterID: "serial",
        transportMode: .usb,
        connectionTransport: .serial,
        displayName: "USB Adapter",
        systemIdentifier: "/dev/cu.usbserial"
    )

    /// 初期化で得られる判定結果です。
    static let evidence = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)

    /// 別の初期化で得られる判定結果です(古い結果との区別に使います)。
    static let otherEvidence = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Clone, monitorProbeOutcome: nil)

    /// 車両から読み取るVINです。
    static let vin = "JN1AZ34D63M000001"

    /// 基準時刻から指定秒数進めた時刻を返します。
    ///
    /// 責務: 基準時刻からの相対秒数を時刻へ変換します。
    /// - Parameter seconds: 基準時刻からの秒数。
    /// - Returns: 基準時刻に秒数を足した時刻。
    nonisolated static func date(_ seconds: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(seconds)
    }

    /// 指定した確認進行状況を返します。
    ///
    /// 責務: 確認窓の終了時刻・回数・段階からテスト用の確認進行状況を組み立てます。
    /// - Parameters:
    ///   - windowEndsAt: 確認窓の終了時刻。既定は基準時刻+10分。
    ///   - attemptCount: 確認回数。
    ///   - phase: 低頻度確認中か休止中か。
    ///   - evidence: アダプター判定結果。
    /// - Returns: 確認進行状況。
    static func confirmation(
        windowEndsAt: Date = date(600),
        attemptCount: Int = 1,
        phase: AdapterLinkVehicleConfirmationPhase = .probing,
        evidence: AcquisitionAdapterProbeEvidence = evidence
    ) -> AdapterLinkVehicleConfirmation {
        AdapterLinkVehicleConfirmation(
            adapterProbeEvidence: evidence,
            windowEndsAt: windowEndsAt,
            attemptCount: attemptCount,
            phase: phase
        )
    }

    /// 検知した車両の観測値です。
    static let detectedVehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: evidence, vin: vin)

    /// 全ての状態の種類と段階を1つずつ並べた代表値です(standby から finishing まで8件)。
    static var allStates: [AdapterLinkSupervisionState] {
        [
            .standby,
            .initializing(linkReadyAt: referenceDate),
            .confirmingVehicle(confirmation(phase: .probing)),
            .confirmingVehicle(confirmation(phase: .paused)),
            .vehicleDetected(AdapterLinkDetectedVehicle(adapterProbeEvidence: evidence, vin: nil), phase: .readingVIN),
            .vehicleDetected(detectedVehicle, phase: .awaitingRecordingStart),
            .recording(detectedVehicle),
            .finishing,
        ]
    }

    /// 遷移へ渡す条件を返します。既定は「稼働中・BLEリンク開始済み・直前 ready・基準時刻」です。
    ///
    /// 責務: テストごとに変えたい条件だけを引数で差し替えた条件値を組み立てます。
    /// - Parameters:
    ///   - isSupervisionStarted: 監視が開始済みか。
    ///   - isSignedIn: サインイン済みか。
    ///   - defaultAdapterPreference: 保存済みの既定アダプター設定。
    ///   - linkPreference: リンクを開始したときの接続対象。
    ///   - linkState: 処理直前のリンク状態。
    ///   - now: 現在時刻。
    ///   - isExternalAdapterUseActive: 手動接続がアダプターを使っているか。
    ///   - isForeground: アプリが前面にいるか。
    ///   - lastVehicleConfirmationSentAt: 最後に車両確認を送った時刻。
    /// - Returns: 遷移の条件。
    static func conditions(
        isSupervisionStarted: Bool = true,
        isSignedIn: Bool = true,
        defaultAdapterPreference: DefaultAdapterPreference? = blePreference,
        linkPreference: DefaultAdapterPreference? = blePreference,
        linkState: AdapterLinkState = .ready,
        now: Date = referenceDate,
        isExternalAdapterUseActive: Bool = false,
        isForeground: Bool = false,
        lastVehicleConfirmationSentAt: Date? = nil
    ) -> AdapterLinkSupervisionConditions {
        AdapterLinkSupervisionConditions(
            isSupervisionStarted: isSupervisionStarted,
            isSignedIn: isSignedIn,
            defaultAdapterPreference: defaultAdapterPreference,
            linkPreference: linkPreference,
            linkState: linkState,
            now: now,
            isExternalAdapterUseActive: isExternalAdapterUseActive,
            isForeground: isForeground,
            lastVehicleConfirmationSentAt: lastVehicleConfirmationSentAt
        )
    }

    /// 見張り中の抑止状態です。
    ///
    /// 責務: 連続した無応答の数と見張りの終わりの時刻を指定した抑止状態を返します。
    /// - Parameters:
    ///   - noResponses: 連続した無応答の数。
    ///   - endsAt: 見張りをやめる時刻。既定は基準時刻から8時間後。
    /// - Returns: 抑止状態。
    static func watching(noResponses: Int = 0, endsAt: Date = date(heldWatchSeconds)) -> AdapterLinkSupervisionState {
        .heldAfterUserStop(AdapterLinkHeldWatch(consecutiveNoResponses: noResponses, phase: .watching(endsAt: endsAt)))
    }

    /// 仕様から導いた、BLE接続対象と検知車両に対する記録開始要求です。
    ///
    /// 責務: 接続終端(BLE・既定アダプターの識別子と名称)・VIN・判定結果を仕様どおりに組み立てます。
    /// - Parameters:
    ///   - preference: リンクの接続対象。
    ///   - vin: 読み取ったVIN。
    ///   - evidence: 初期化時の判定結果。
    /// - Returns: 期待する記録開始要求。
    static func expectedStartRequest(
        preference: DefaultAdapterPreference = blePreference,
        vin: String?,
        evidence: AcquisitionAdapterProbeEvidence = evidence
    ) -> AdapterLinkRecordingStartRequest {
        AdapterLinkRecordingStartRequest(
            endpoint: OBDConnectionEndpoint(
                transport: .bluetoothLowEnergy,
                systemIdentifier: preference.systemIdentifier,
                displayName: preference.displayName
            ),
            vin: vin,
            adapterProbeEvidence: evidence
        )
    }
}
