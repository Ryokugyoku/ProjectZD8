/// PID説明の見出しと4項目の説明行を表す表示内容です。
///
/// iOSのシートとmacOSのポップオーバーで共通の内容です。
nonisolated struct LiveTelemetryPIDHelpContent: Equatable, Sendable {
    /// 説明の1項目です。
    nonisolated struct Row: Equatable, Identifiable, Sendable {
        /// 項目見出しのローカライズキーです。
        let titleKey: String
        /// 項目本文のローカライズキーです。
        let bodyKey: String

        /// 一覧表示で使う識別子です。見出しキーは説明内で一意です。
        var id: String { titleKey }
    }

    /// 説明全体の見出し(PID名称)のローカライズキーです。
    let titleKey: String
    /// 概要・高値時・低値時・相関の順の4項目です。
    let rows: [Row]

    /// PIDサンプルから説明内容を生成します。
    ///
    /// 責務: 1件のPIDサンプルが持つ説明キーを、決まった順の4項目へ並べます。
    /// - Parameter sample: 説明するPIDサンプル。
    init(sample: OBDPIDSample) {
        titleKey = sample.nameKey
        rows = [
            Row(titleKey: "telemetry.help.summary", bodyKey: sample.summaryKey),
            Row(titleKey: "telemetry.help.high", bodyKey: sample.highValueKey),
            Row(titleKey: "telemetry.help.low", bodyKey: sample.lowValueKey),
            Row(titleKey: "telemetry.help.correlation", bodyKey: sample.correlationKey),
        ]
    }
}
