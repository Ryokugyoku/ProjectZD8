import Foundation

/// セッション終了の直後に、走行ルート(位置の軌跡)のアップロードを1回起動します(Raw の `.sessionUploadRequested` に相当)。
///
/// - 自動アップロードがオフ、実行処理が未接続、セッションのアカウントが空の時は何もしません。
/// - 実行中に要求された時は「もう1回」の印だけを付け、終了後に1回だけ再実行します(何回要求されても追加は1回)。
/// - 結果は件数とエラーの domain・code だけを診断へ残します。失敗しても次の要求は実行し、取りこぼしは後処理で再送されます。
@MainActor
final class ConnectionSessionLocationTrackUploadTrigger {
    /// 結果を残す診断です。
    private let diagnostics: any ConnectionSessionLocationTrackSyncDiagnosticsPort
    /// 後から結び付けるアップロードの実行処理です。未接続なら `nil`。
    private var upload: (@MainActor (String) async throws -> ConnectionSessionLocationTrackUploadReport)?
    /// 実行中のアップロードです。実行中でなければ `nil`。
    private var runningTask: Task<Void, Never>?
    /// 実行中に要求された時の再実行の対象アカウントです。印が無ければ `nil`。
    private var pendingAccountIdentifier: String?

    /// 診断を固定して生成します。
    ///
    /// 責務: 実行処理が未接続の状態で、結果の記録先だけを構成します。
    /// - Parameter diagnostics: 結果を残す診断。
    init(diagnostics: any ConnectionSessionLocationTrackSyncDiagnosticsPort) {
        self.diagnostics = diagnostics
    }

    /// 実行中のアップロードを取消します。
    deinit {
        runningTask?.cancel()
    }

    /// アップロードの実行処理を結び付けます。
    ///
    /// 責務: 組み立ての後段で作られる実行処理を保持し、以後の要求で使えるようにします。
    /// - Parameter upload: 指定アカウントの軌跡をアップロードする処理。
    func connect(upload: @escaping @MainActor (String) async throws -> ConnectionSessionLocationTrackUploadReport) {
        self.upload = upload
    }

    /// セッションの終了を受けて、条件を満たせばアップロードを起動します。
    ///
    /// 責務: 実行条件を確かめ、実行中でなければ起動し、実行中なら再実行の印を付けます。
    /// - Parameters:
    ///   - session: 終了したセッション。
    ///   - automaticUploadEnabled: 自動アップロードの設定がオンなら `true`。
    func sessionDidEnd(_ session: ConnectionSession, automaticUploadEnabled: Bool) {
        guard automaticUploadEnabled, upload != nil, !session.accountIdentifier.isEmpty else {
            return
        }
        guard runningTask == nil else {
            pendingAccountIdentifier = session.accountIdentifier
            return
        }
        start(accountIdentifier: session.accountIdentifier)
    }

    /// 実行中のアップロード(再実行分を含む)がすべて終わるまで待ちます。テスト用です。
    ///
    /// 責務: 実行中の Task の終了を、再実行で置き換わった Task も含めて順に待ちます。
    func waitUntilIdle() async {
        while let task = runningTask {
            await task.value
        }
    }

    /// アップロードを1回起動します。
    ///
    /// 責務: 実行処理と診断だけを捕まえた Task を起動し、終了時に再実行の印を確かめさせます。
    /// - Parameter accountIdentifier: 対象アカウント。
    private func start(accountIdentifier: String) {
        guard let upload else {
            return
        }
        let diagnostics = diagnostics
        runningTask = Task { [weak self] in
            await Self.perform(upload, accountIdentifier: accountIdentifier, diagnostics: diagnostics)
            self?.runDidFinish()
        }
    }

    /// 1回の実行の終了を反映します。
    ///
    /// 責務: 実行中の印を外し、再実行の印があれば印を消して1回だけ起動し直します。
    private func runDidFinish() {
        runningTask = nil
        guard let accountIdentifier = pendingAccountIdentifier else {
            return
        }
        pendingAccountIdentifier = nil
        start(accountIdentifier: accountIdentifier)
    }

    /// アップロードを実行し、結果を診断へ残します。
    ///
    /// 責務: 成功は件数を、失敗は NSError の domain と code を記録します。
    /// - Parameters:
    ///   - upload: 実行処理。
    ///   - accountIdentifier: 対象アカウント。
    ///   - diagnostics: 結果を残す診断。
    private static func perform(
        _ upload: @MainActor (String) async throws -> ConnectionSessionLocationTrackUploadReport,
        accountIdentifier: String,
        diagnostics: any ConnectionSessionLocationTrackSyncDiagnosticsPort
    ) async {
        do {
            let report = try await upload(accountIdentifier)
            diagnostics.immediateUploadSucceeded(uploadedCount: report.uploadedSessionIDs.count)
        } catch {
            let nsError = error as NSError
            diagnostics.immediateUploadFailed(errorDomain: nsError.domain, errorCode: nsError.code)
        }
    }
}
