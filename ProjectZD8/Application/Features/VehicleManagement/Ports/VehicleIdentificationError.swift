/// OBD車両識別処理が完了できなかった理由です。
enum VehicleIdentificationError: Error, Equatable {
    /// 車両識別処理のうち失敗した単一段階です。
    enum Stage: Equatable {
        /// 選択された接続終端を検証しています。
        case endpointValidation
        /// 選択された接続終端のTransportを生成しています。
        case transportCreation
        /// 選択されたシリアル終端を開いています。
        case transportOpen
        /// アダプターを既知の初期状態へ戻しています。
        case adapterReset
        /// アダプターの表示・プロトコル設定を適用しています。
        case adapterConfiguration
        /// 標準アダプター識別文字列を取得しています。
        case adapterIdentity
        /// Service 09 PID 02へ車両識別子を要求しています。
        case vehicleIdentificationRequest
        /// Service 09 PID 02応答を識別子へ復元しています。
        case vehicleIdentificationParsing
        /// 選択済みOBDプロトコルの説明を取得しています。
        case protocolDescription
    }

    /// 失敗段階で観測した単一原因です。
    enum Cause: Equatable {
        /// 対象処理の実装が利用できません。
        case unavailable
        /// 選択された物理通信方式を使用できません。
        case transportUnsupported
        /// 物理接続または送受信を完了できませんでした。
        case connectionFailed
        /// 応答が期限内に完了しませんでした。
        case responseTimedOut
        /// アダプターまたは車両が要求を拒否しました。
        case commandRejected
        /// 応答を期待形式として復元できませんでした。
        case malformedResponse
    }

    /// 実OBD識別実装がCompositionへまだ提供されていません。
    case unavailable
    /// 選択された物理通信方式をこのプラットフォームでは使用できません。
    case transportUnsupported
    /// 選択済みOBDアダプターのUSBシリアル終端を開けませんでした。
    case connectionFailed
    /// アダプターが期限内に完全な応答を返しませんでした。
    case responseTimedOut
    /// アダプターが要求を理解しないか車両からデータを取得できませんでした。
    case commandRejected
    /// 応答を規格上の車両識別情報として復元できませんでした。
    case malformedResponse
    /// PID専用テーブルを安全に準備できませんでした。
    case pidCatalogUnavailable
    /// VINを取得できなかったため登録照合を継続できません。
    case vinUnavailable
    /// 車両識別処理が特定可能な段階と原因で失敗しました。
    case stageFailed(Stage, Cause)
}
