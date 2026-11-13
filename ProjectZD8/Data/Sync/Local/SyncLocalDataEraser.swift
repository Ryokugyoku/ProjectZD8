import Foundation
import GRDB

/// この端末の全ユーザーデータと同期の管理情報を消去します。
nonisolated struct SyncLocalDataEraser: Sendable {
    private let database: AppDatabase
    private let photoFiles: PhotoFileStore

    /// 責務: 共有データベースと写真ストアを消去する消去器を生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore) {
        self.database = database
        self.photoFiles = photoFiles
    }

    /// 責務: 全テーブルの行(車両から連鎖する全ての子を含む)、同期管理情報、写真ファイルを削除します。
    /// - Throws: データベースまたはファイルの削除に失敗した場合のエラー。
    func eraseAll() throws {
        try database.writer.write { db in
            // 外部キーの連鎖で photos / maintenance_records / sessions / session_pids /
            // session_samples / vehicle_pid_settings も消えます。明示的にも消して取り残しを防ぎます。
            for table in ["session_samples", "session_pids", "sessions", "maintenance_records", "photos", "vehicle_pid_settings", "vehicles", "sync_records", "sync_state"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        let directory = photoFiles.directory
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
