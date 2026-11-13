/// アダプター記述の列に対する重複除外です。
nonisolated extension Sequence where Element == AdapterDescriptor {
    /// 責務: 同じ `id` の記述を先着優先で1件にまとめ、入力順を保った配列を返します。
    func uniquedByID() -> [AdapterDescriptor] {
        var identifiers: Set<String> = []
        return filter { identifiers.insert($0.id).inserted }
    }
}
