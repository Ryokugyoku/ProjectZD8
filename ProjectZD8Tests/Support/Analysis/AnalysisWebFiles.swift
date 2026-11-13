import Foundation

/// 同梱するWebリソースのファイル名の一覧です(拡張子なし)。
nonisolated enum AnalysisWebFiles {
    /// 配信するスクリプトです。
    static let scripts = [
        "analysis-app", "analysis-binning", "analysis-chart-bars", "analysis-chart-heat", "analysis-chart-scatter", "analysis-chart-time",
        "analysis-csv", "analysis-decimate", "analysis-demo", "analysis-derive", "analysis-dom", "analysis-expr", "analysis-host",
        "analysis-i18n", "analysis-join", "analysis-model", "analysis-segment", "analysis-stats", "analysis-theme", "analysis-ui",
        "analysis-view-compare", "analysis-view-derived", "analysis-view-distribution", "analysis-view-export", "analysis-view-maptable",
        "analysis-view-overview", "analysis-view-quality", "analysis-view-scatter", "analysis-view-timeseries", "analysis-view-trends"
    ]
}
