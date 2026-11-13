/// 永続化データの変更通知の契約です。同期による取り込みも含め、書き込みの都度通知します。
nonisolated protocol StoreChangeObserving: Sendable {
    /// 責務: 指定領域のいずれかが変更されるたびに要素を流すストリームを返します。購読開始時には流しません。
    func changes(in areas: Set<StoreArea>) -> AsyncStream<Void>
}
