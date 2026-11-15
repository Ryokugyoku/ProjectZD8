/// アプリのルートで1回だけ生成し、各モデルが共有する保存先と接続セッション系のモデルです。
///
/// `ApplicationRootAssembly.makeFoundation` が生成します。PID継続取得と車両管理のモデルは、
/// この土台の同じインスタンスへOSごとの配線で結び付けます。
@MainActor
struct ApplicationRootFoundation {
    /// 取得区間を通知する匿名計測境界です。
    let performanceEvents: any AcquisitionPerformanceEventPort
    /// プロセス内で共有する製品DB接続です。
    let database: ApplicationDatabaseConnection
    /// 接続session・取得証拠・チャンク・区間・欠損の保存先一式です。
    let storage: ConnectionSessionStorageDependencies
    /// 接続履歴のモデルです。
    let history: ConnectionHistoryModel
    /// 保存済みPIDログ解析のモデルです。
    let analysis: SessionLogAnalysisModel
    /// 接続セッションのライフサイクルのモデルです。
    let lifecycle: ConnectionSessionLifecycleModel
}
