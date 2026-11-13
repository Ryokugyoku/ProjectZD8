import Foundation

/// iCloud Key-Value Storeへ必要な最小操作を抽象化します。
protocol UbiquitousKeyValueStorePort: AnyObject {
    /// 指定キーのデータを返します。
    ///
    /// 責務: 1件のキーに対応する同期データを読み込みます。
    /// - Parameter key: 読み込む同期キー。
    /// - Returns: 保存済みデータ。未保存の場合は `nil`。
    func data(forKey key: String) -> Data?

    /// 指定キーへデータを保存します。
    ///
    /// 責務: 1件の同期データを指定キーへ置き換え保存します。
    /// - Parameters:
    ///   - data: 保存するデータ。
    ///   - key: 保存先の同期キー。
    func setData(_ data: Data, forKey key: String)

    /// 指定キーの同期データを削除します。
    ///
    /// 責務: 1件のキーに対応する同期データを存在しない状態へします。
    /// - Parameter key: 削除する同期キー。
    func removeObject(forKey key: String)

    /// ローカルとiCloud間の保留中変更を同期するよう要求します。
    ///
    /// 責務: iCloud Key-Value Storeへ1回の同期要求を通知します。
    /// - Returns: 同期要求を受理した場合は `true`。
    @discardableResult
    func synchronize() -> Bool
}

/// FoundationのiCloud Key-Value Storeを共通同期境界へ適合させます。
extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStorePort {
    /// 指定キーへ同期データを保存します。
    ///
    /// 責務: `Data`値1件をFoundationのiCloud Key-Value Storeへ渡します。
    /// - Parameters:
    ///   - data: 保存するデータ。
    ///   - key: 保存先の同期キー。
    func setData(_ data: Data, forKey key: String) {
        set(data, forKey: key)
    }
}
