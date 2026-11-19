/// ホームのアダプターカードに出す名称・状態・記号・主操作です。
///
/// iOSとmacOSで共通の判定です。OSごとの接続先の規則は呼び出し側が `connectionEndpoint` に反映します。
nonisolated struct HomeAdapterCardContent: Equatable, Sendable {
    /// アダプター名が未設定の時に出すローカライズキーです。
    static let notConfiguredTitleKey = "home.adapter.not_configured"

    /// 保存済みアダプターの名称です。未設定なら `nil` で、View は `notConfiguredTitleKey` を出します。
    let adapterName: String?
    /// アダプターの状態を表すローカライズキーです。
    let statusKey: String
    /// 状態を補助するSF Symbol名です。
    let statusSymbol: String
    /// アダプターを表すSF Symbol名です。
    let adapterSymbol: String
    /// 保存済みアダプターを最新の探索で検出できたかどうかです。
    let isDetected: Bool
    /// カードの主操作です。
    let primaryAction: HomeAdapterPrimaryAction

    /// アダプターの接続可否と接続先からカードの内容を生成します。
    ///
    /// 責務: 保存済みアダプターの検出状態を、カードの文言キー・記号・主操作へ変換します。
    /// - Parameters:
    ///   - availability: 保存済みアダプターの現在の接続可否。
    ///   - connectionEndpoint: OSごとの規則で選んだ接続先。接続できなければ `nil`。
    init(availability: DefaultAdapterAvailability, connectionEndpoint: OBDConnectionEndpoint?) {
        adapterName = availability.displayName
        isDetected = availability.isDetected
        statusKey = Self.statusKey(for: availability)
        statusSymbol = isDetected ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        adapterSymbol = isDetected ? "cable.connector.horizontal" : "cable.connector.slash"
        primaryAction = isDetected ? .connect(connectionEndpoint) : .setupAdapter
    }

    /// 接続可否に対応する状態の文言キーを返します。
    ///
    /// 責務: 1件の接続可否を検出済み・未検出・未設定の文言キーへ変換します。
    /// - Parameter availability: 保存済みアダプターの現在の接続可否。
    /// - Returns: 状態を表すローカライズキー。
    private static func statusKey(for availability: DefaultAdapterAvailability) -> String {
        switch availability {
        case .detected: "home.adapter.detected"
        case .notDetected: "home.adapter.not_detected"
        case .notConfigured: "home.adapter.setup_required"
        }
    }
}
