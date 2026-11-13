/// 保存済みデフォルトアダプターの現在の接続可否を表します。
nonisolated enum DefaultAdapterAvailability: Equatable, Sendable {
    /// デフォルトアダプターが設定されていません。
    case notConfigured

    /// 保存済みデフォルトアダプターが最新探索で検出されていません。
    case notDetected(displayName: String)

    /// 保存済みデフォルトアダプターが最新探索で検出され、接続終端を利用できます。
    case detected(displayName: String, endpoint: OBDConnectionEndpoint)

    /// デフォルトアダプターが保存済みかどうかです。
    var hasDefaultAdapter: Bool {
        switch self {
        case .notConfigured:
            false
        case .notDetected, .detected:
            true
        }
    }

    /// HOMEに表示するデフォルトアダプター名称です。
    var displayName: String? {
        switch self {
        case .notConfigured:
            nil
        case let .notDetected(displayName), let .detected(displayName, _):
            displayName
        }
    }

    /// 保存済みデフォルトアダプターを最新探索で検出できたかどうかです。
    var isDetected: Bool {
        if case .detected = self {
            true
        } else {
            false
        }
    }

    /// 最新探索で検出できたデフォルトアダプターの接続終端です。
    var connectionEndpoint: OBDConnectionEndpoint? {
        guard case let .detected(_, endpoint) = self else { return nil }
        return endpoint
    }

    /// 保存設定と最新探索候補から現在の接続可否を生成します。
    ///
    /// 責務: 保存済みデフォルトと一致する最新候補だけを接続可能状態へ変換します。
    /// - Parameters:
    ///   - preference: 保存済みデフォルトアダプター設定。
    ///   - detectedAdapter: 最新探索でプライマリーとして照合された候補。
    init(
        preference: DefaultAdapterPreference?,
        detectedAdapter: DiscoveredAdapter?
    ) {
        guard let preference else {
            self = .notConfigured
            return
        }
        guard let detectedAdapter, preference.matches(detectedAdapter) else {
            self = .notDetected(displayName: preference.displayName)
            return
        }
        self = .detected(
            displayName: preference.displayName,
            endpoint: OBDConnectionEndpoint(adapter: detectedAdapter)
        )
    }
}
