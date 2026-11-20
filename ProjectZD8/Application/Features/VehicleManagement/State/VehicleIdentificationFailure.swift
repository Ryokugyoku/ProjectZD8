/// 1件の車両識別失敗を、Platformが描画する失敗段階と原因文言キーへ変換した結果です。
struct VehicleIdentificationFailure: Equatable {
    /// 完了できなかった車両識別段階です。段階を特定できない失敗では `nil` です。
    let stage: VehicleIdentificationError.Stage?
    /// 失敗をユーザーへ説明するローカライズキーです。
    let failureKey: String

    /// 識別ユースケースが投げた失敗から表示用の失敗内容を生成します。
    ///
    /// 責務: 1件の識別失敗を型付き段階と原因ローカライズキーへ変換し、未知の失敗はOBD利用不可として扱います。
    /// - Parameter error: 車両識別ユースケースが投げた失敗。
    init(error: any Error) {
        guard let identificationError = error as? VehicleIdentificationError else {
            self.init(stage: nil, failureKey: "garage.error.obd_unavailable")
            return
        }
        if case let .stageFailed(stage, cause) = identificationError {
            self.init(stage: stage, failureKey: Self.failureKey(for: cause))
            return
        }
        self.init(stage: nil, failureKey: Self.failureKey(for: identificationError))
    }

    /// 段階と文言キーを指定して失敗内容を生成します。
    ///
    /// 責務: 変換済みの段階と文言キー1組を保持します。
    /// - Parameters:
    ///   - stage: 完了できなかった車両識別段階。
    ///   - failureKey: 失敗を説明するローカライズキー。
    private init(stage: VehicleIdentificationError.Stage?, failureKey: String) {
        self.stage = stage
        self.failureKey = failureKey
    }

    /// 段階を伴わない識別失敗を文言キーへ変換します。
    ///
    /// 責務: 段階なしの識別失敗1件を、対応するローカライズキーへ変換します。
    /// - Parameter error: 段階を伴わない車両識別失敗。
    /// - Returns: 失敗を説明するローカライズキー。
    private static func failureKey(for error: VehicleIdentificationError) -> String {
        switch error {
        case .vinUnavailable: "garage.error.vin_unavailable"
        case .pidCatalogUnavailable: "garage.error.pid_catalog"
        case .connectionFailed: "garage.error.connection"
        case .responseTimedOut: "garage.error.timeout"
        case .commandRejected: "garage.error.command_rejected"
        case .malformedResponse: "garage.error.malformed_response"
        case .unavailable, .transportUnsupported, .stageFailed: "garage.error.obd_unavailable"
        }
    }

    /// 失敗段階で観測した原因を文言キーへ変換します。
    ///
    /// 責務: 1件の段階別原因を、対応するローカライズキーへ変換します。
    /// - Parameter cause: 失敗段階で観測した単一原因。
    /// - Returns: 原因を説明するローカライズキー。
    private static func failureKey(for cause: VehicleIdentificationError.Cause) -> String {
        switch cause {
        case .unavailable, .transportUnsupported: "garage.error.obd_unavailable"
        case .connectionFailed: "garage.error.connection"
        case .responseTimedOut: "garage.error.timeout"
        case .commandRejected: "garage.error.command_rejected"
        case .malformedResponse: "garage.error.malformed_response"
        }
    }
}
