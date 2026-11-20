import Foundation

/// セッション解析画面の文字列整形とローカライズキーの選択を返します。
///
/// iOS と macOS の解析画面で共通に使う純粋な表示変換です。ローカライズキーは `String` で返し、View 側で `LocalizedStringKey` に包みます。
struct SessionLogAnalysisTextFormatter {
    /// 数値・書式の整形に使う Locale です。
    private let locale: Locale

    /// 整形に使う Locale を固定して生成します。
    ///
    /// 責務: 書式付き文字列と数値の整形に使う Locale を保持します。
    /// - Parameter locale: 整形に使う Locale。既定は現在の設定に追従する Locale。
    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// 部品・系統分類の見出しキーを返します。
    ///
    /// 責務: 1件の部品・系統分類をローカライズキーへ変換します。
    /// - Parameter component: 表示する部品・系統分類。
    /// - Returns: 対応する見出しキー。
    func componentTitleKey(_ component: SessionComponentInsight.Component) -> String {
        switch component {
        case .electrical: "analysis.components.electrical.title"
        case .thermal: "analysis.components.thermal.title"
        case .fuelAndIntake: "analysis.components.fuel_intake.title"
        case .exhaust: "analysis.components.exhaust.title"
        case .diagnostics: "analysis.components.diagnostics.title"
        }
    }

    /// 部品・系統分類の説明キーを返します。
    ///
    /// 責務: 1件の部品・系統分類を安全な観察目的のローカライズキーへ変換します。
    /// - Parameter component: 説明する部品・系統分類。
    /// - Returns: 対応する説明キー。
    func componentDescriptionKey(_ component: SessionComponentInsight.Component) -> String {
        switch component {
        case .electrical: "analysis.components.electrical.body"
        case .thermal: "analysis.components.thermal.body"
        case .fuelAndIntake: "analysis.components.fuel_intake.body"
        case .exhaust: "analysis.components.exhaust.body"
        case .diagnostics: "analysis.components.diagnostics.body"
        }
    }

    /// 部品・系統分類の SF Symbol 名を返します。
    ///
    /// 責務: 1件の部品・系統分類を識別用シンボルへ変換します。
    /// - Parameter component: 表示する部品・系統分類。
    /// - Returns: 対応する SF Symbol 名。
    func componentSymbol(_ component: SessionComponentInsight.Component) -> String {
        switch component {
        case .electrical: "bolt.12"
        case .thermal: "thermometer.medium"
        case .fuelAndIntake: "wind"
        case .exhaust: "aqi.medium"
        case .diagnostics: "wrench.and.screwdriver"
        }
    }

    /// PID 組を散布図で観察できる内容のローカライズキーを返します。
    ///
    /// 責務: 1件の既定 PID 相関候補へ対応する観察目的を選択します。
    /// - Parameter relationship: 解説対象の PID 相関候補。
    /// - Returns: PID 組固有の観察目的キー。既定の組でなければ共通の読み方のキー。
    func relationshipGuideKey(_ relationship: SessionPIDRelationship) -> String {
        switch (
            relationship.xSeries.id.service,
            relationship.xSeries.id.pid,
            relationship.ySeries.id.service,
            relationship.ySeries.id.pid
        ) {
        case (0x01, 0x0C, 0x01, 0x0D): "analysis.relationship.guide.rpm_speed"
        case (0x01, 0x0C, 0x01, 0x04): "analysis.relationship.guide.rpm_load"
        case (0x01, 0x0C, 0x01, 0x10): "analysis.relationship.guide.rpm_maf"
        case (0x01, 0x11, 0x01, 0x04): "analysis.relationship.guide.throttle_load"
        case (0x01, 0x06, 0x01, 0x07): "analysis.relationship.guide.trim_banks"
        case (0x01, 0x0D, 0x21, 0x17): "analysis.relationship.guide.speed_zd8_atf"
        default: "analysis.relationship.guide.common"
        }
    }

    /// PID 系列の定義名または識別子を返します。
    ///
    /// 責務: 1件の PID 系列をローカライズ済み表示名へ変換します。
    /// - Parameter series: 表示名を求める PID 系列。
    /// - Returns: 定義名。定義名が無ければ Service/PID 識別子。
    func seriesName(_ series: SessionPIDSeries) -> String {
        series.nameKey.map { String(localized: String.LocalizationValue($0)) }
            ?? pidLabel(service: series.id.service, pid: series.id.pid)
    }

    /// 散布図の2軸名を短い組名へ変換します。
    ///
    /// 責務: 1件の PID 相関候補を横軸名と縦軸名の表示文字列へ変換します。
    /// - Parameter relationship: 表示する PID 相関候補。
    /// - Returns: 2件の PID 名を `×` で結んだ文字列。
    func relationshipName(_ relationship: SessionPIDRelationship) -> String {
        "\(seriesName(relationship.xSeries)) × \(seriesName(relationship.ySeries))"
    }

    /// PID 識別子を16進表現へ変換します。
    ///
    /// 責務: 1件の Service/PID をローカライズ可能な表示識別子へ変換します。
    /// - Parameters:
    ///   - service: OBD Service 番号。
    ///   - pid: Service 内 PID 番号。
    /// - Returns: Service と PID を16進表記した文字列。
    func pidLabel(service: UInt8, pid: UInt8) -> String {
        String(format: String(localized: "analysis.pid.identifier"), locale: locale, service, pid)
    }

    /// PID 系列の最新・最小・平均・最大を1行へ整形します。
    ///
    /// 責務: 1件の PID 系列統計を部品カード用の短い表示へ変換します。
    /// - Parameter series: 整形する PID 系列。
    /// - Returns: 統計値を単位付きで示す文字列。
    func statisticsText(_ series: SessionPIDSeries) -> String {
        String(
            format: String(localized: "analysis.components.statistics"),
            locale: locale,
            series.latestValue,
            series.minimumValue,
            series.averageValue,
            series.maximumValue,
            series.unit
        )
    }

    /// 数値帯を下限と上限を持つ表示文字列へ変換します。
    ///
    /// 責務: 1件の数値帯をローカライズ済み範囲表記へ変換します。
    /// - Parameters:
    ///   - band: 表示する数値帯。
    ///   - key: 単位ごとの書式キー。
    /// - Returns: 下限以上かつ上限未満を表す文字列。
    func bandText(_ band: SessionDurationBand, key: String) -> String {
        String(
            format: String(localized: String.LocalizationValue(key)),
            locale: locale,
            band.lowerBound,
            band.upperBound
        )
    }

    /// 秒数を時分秒の短い表示へ変換します。
    ///
    /// 責務: 1件の秒数を、1時間以上は時分、1分以上は分秒、それ未満は秒の省略単位形式へ変換します。
    /// - Parameter duration: 表示する秒数。
    /// - Returns: 最大2単位の省略単位形式。整形できなければ取得不可の文言。
    func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute] : duration >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? String(localized: "analysis.value.unavailable")
    }

    /// 数値と単位を現在ロケールの短い表示へ変換します。
    ///
    /// 責務: 1件の有限数値と単位を小数0〜1桁の表示へ変換します。
    /// - Parameters:
    ///   - value: 表示する数値。
    ///   - unit: PID 定義の単位。
    /// - Returns: 数値と単位を空白で結合した文字列。
    func measurementText(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) \(unit)"
    }

    /// セッション開始から終了までの接続時間を表示文字列へ変換します。
    ///
    /// 責務: 1件のセッションの接続時間を、進行中の文言または負の値を0に切り詰めた時間表示へ変換します。
    /// - Parameter session: 接続時間を表示するセッション。
    /// - Returns: 終了時刻が無ければ進行中の文言、あれば時間表示。
    func sessionDurationText(_ session: ConnectionSession) -> String {
        guard let endedAt = session.endedAt else { return String(localized: "analysis.value.in_progress") }
        return durationText(max(endedAt.timeIntervalSince(session.startedAt), 0))
    }

    /// 車速観測から推定した走行時間を表示文字列へ変換します。
    ///
    /// 責務: 1件の走行サマリーの推定走行時間を、時間表示または取得不可の文言へ変換します。
    /// - Parameter summary: 推定走行時間を持つ走行サマリー。
    /// - Returns: 推定値があれば時間表示、無ければ取得不可の文言。
    func movingDurationText(_ summary: SessionPerformanceSummary) -> String {
        summary.estimatedMovingDuration.map(durationText) ?? String(localized: "analysis.value.unavailable")
    }

    /// 保存済み距離差または車速積算の参考距離を表示文字列へ変換します。
    ///
    /// 責務: 記録距離・推定距離・取得不可の3分岐から距離の表示を1つ選びます。
    /// - Parameters:
    ///   - session: 記録距離を持ち得るセッション。
    ///   - summary: 推定距離を持ち得る走行サマリー。
    /// - Returns: 記録距離があれば km 表示、無ければ推定距離の書式、どちらも無ければ取得不可の文言。
    func distanceText(session: ConnectionSession, summary: SessionPerformanceSummary) -> String {
        if let distance = session.recordedDistanceKilometers { return measurementText(distance, unit: "km") }
        guard let distance = summary.estimatedDistanceKilometers else {
            return String(localized: "analysis.value.unavailable")
        }
        return String(format: String(localized: "analysis.value.estimated_distance"), locale: locale, distance)
    }

    /// 距離値の取得元に対応する見出しキーを返します。
    ///
    /// 責務: 記録距離の有無から距離の見出しキーを選びます。
    /// - Parameter session: 記録距離を持ち得るセッション。
    /// - Returns: 記録距離があれば `analysis.overview.distance`、無ければ `analysis.overview.estimated_distance`。
    func distanceTitleKey(_ session: ConnectionSession) -> String {
        session.recordedDistanceKilometers == nil ? "analysis.overview.estimated_distance" : "analysis.overview.distance"
    }
}
