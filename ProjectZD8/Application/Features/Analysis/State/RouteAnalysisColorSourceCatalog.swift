/// そのセッションで選べる色分けの元(指標と重ね合わせ)の一覧を作ります。
///
/// - 指標は `RouteAnalysisColorMetric.allCases` の順に必ずすべて並べ、PID の値の列が1件以上ある時だけ選べます。
///   選べない指標は理由のキーを持ちます。GPS の速さなど別の値での代用はしません。
/// - 重ね合わせは、渡された順に指標の後ろへ並べ、常に選べます。
nonisolated struct RouteAnalysisColorSourceCatalog: Sendable {
    /// 値の列が無い指標の、選べない理由のキーです。
    private static let metricUnavailableKey = "analysis.route.metric.unavailable"

    /// 色分けの元の選択肢を並べます。
    ///
    /// 責務: 指標ごとに値の列の有無で選べるかを決め、その後ろに重ね合わせを並べます。
    /// - Parameters:
    ///   - valueSeries: 指標ごとの値の列(無い指標は選べない)。
    ///   - overlays: 重ね合わせ(5c の判定結果など)。
    /// - Returns: 指標(4つ)の後に重ね合わせが続く選択肢。
    func options(
        valueSeries: [RouteAnalysisColorMetric: RouteAnalysisValueSeries],
        overlays: [RouteAnalysisOverlay]
    ) -> [RouteAnalysisColorSourceOption] {
        let metricOptions = RouteAnalysisColorMetric.allCases.map { metric in
            let isEnabled = !(valueSeries[metric]?.isEmpty ?? true)
            return RouteAnalysisColorSourceOption(
                source: .metric(metric),
                titleKey: metric.titleKey,
                isEnabled: isEnabled,
                disabledReasonKey: isEnabled ? nil : Self.metricUnavailableKey
            )
        }
        let overlayOptions = overlays.map { overlay in
            RouteAnalysisColorSourceOption(source: .overlay(id: overlay.id), titleKey: overlay.titleKey, isEnabled: true, disabledReasonKey: nil)
        }
        return metricOptions + overlayOptions
    }

    /// 既定で選ぶ色分けの元を返します。
    ///
    /// 責務: 選べる最初の指標を選びます。重ね合わせは既定にしません。
    /// - Parameter options: 色分けの元の選択肢。
    /// - Returns: 選べる最初の指標。選べる指標が無ければ `nil`。
    func defaultSource(in options: [RouteAnalysisColorSourceOption]) -> RouteAnalysisColorSource? {
        options.first { option in
            guard option.isEnabled, case .metric = option.source else { return false }
            return true
        }?.source
    }
}
