/// 常駐リンク上のバイトストリームを1利用者が占有していることを示す占有権です。
///
/// 書き込みと読取はこの値を持つ利用者だけが行えます。解放後の値は再利用できません。
nonisolated struct AdapterLinkByteStreamLease: Equatable, Sendable {
    /// 占有権ごとに一意な通し番号です。
    let id: UInt64
}
