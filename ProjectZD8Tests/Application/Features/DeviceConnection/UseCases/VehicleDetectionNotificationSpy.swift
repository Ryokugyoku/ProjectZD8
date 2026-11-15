@testable import ProjectZD8

/// 車両検知通知の spy です。準備・提示・取り下げを記録し、[記録開始]の受け口を保持します。
@MainActor
final class VehicleDetectionNotificationSpy: VehicleDetectionNotificationPort {
    /// 準備で返す許可の結果です。
    var authorizationResult = true

    /// 準備が呼ばれた回数です。
    private(set) var prepareCount = 0

    /// 準備で渡された[記録開始]の受け口です。
    private(set) var recordingStartSelected: (@MainActor () -> Void)?

    /// 「車両を検知しました」通知に渡されたVINです(提示順)。
    private(set) var presentedVehicleDetectedVINs: [String?] = []

    /// 「記録を開始しました」通知に渡されたVINです(提示順)。
    private(set) var presentedRecordingStartedVINs: [String?] = []

    /// 取り下げが呼ばれた回数です。
    private(set) var dismissCount = 0

    /// 通知の準備を記録して許可の結果を返します。
    ///
    /// 責務: [記録開始]の受け口を保持し、設定された許可の結果を返します。
    /// - Parameter recordingStartSelected: [記録開始]が選ばれたときに呼ぶ処理。
    /// - Returns: 設定された許可の結果。
    func prepare(recordingStartSelected: @escaping @MainActor () -> Void) async -> Bool {
        prepareCount += 1
        self.recordingStartSelected = recordingStartSelected
        return authorizationResult
    }

    /// 検知通知の提示を記録します。
    ///
    /// 責務: 渡されたVINを提示順に記録します。
    /// - Parameter vin: 読み取ったVIN。
    func presentVehicleDetected(vin: String?) {
        presentedVehicleDetectedVINs.append(vin)
    }

    /// 記録開始通知の提示を記録します。
    ///
    /// 責務: 渡されたVINを提示順に記録します。
    /// - Parameter vin: 読み取ったVIN。
    func presentRecordingStarted(vin: String?) {
        presentedRecordingStartedVINs.append(vin)
    }

    /// 取り下げを記録します。
    ///
    /// 責務: 取り下げ回数を数えます。
    func dismiss() {
        dismissCount += 1
    }
}
