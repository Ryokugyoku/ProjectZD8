import GRDB

nonisolated extension AppDatabase {
    /// 責務: 読み取りを実行し、`StoreError` 以外の失敗を `StoreError.ioFailure` へ写像します。
    func storeRead<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.read(block)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.ioFailure
        }
    }

    /// 責務: 1トランザクションで書き込みを実行し、`StoreError` 以外の失敗を `StoreError.ioFailure` へ写像します。
    func storeWrite<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        do {
            return try await writer.write(block)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.ioFailure
        }
    }
}
