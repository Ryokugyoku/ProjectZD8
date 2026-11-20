/// 走行ルートの理由と注記を、ローカライズキー(`history.route.*`)と SF Symbols の名前へ写します。
///
/// キーは `String` で返し、View 側で `LocalizedStringKey` に包みます。
nonisolated struct DrivingRouteTextKeys: Sendable {
    /// 理由ごとのキーの末尾と記号の対応です。
    private struct Entry: Sendable {
        /// `absence.` と `notice.partial.` に続くキーの末尾です。
        let keySuffix: String
        /// 理由に添える SF Symbols の名前です。
        let systemImage: String
    }

    /// すべての理由のキーの末尾と記号です(11種)。
    private static let entries: [DrivingRouteAbsenceReason: Entry] = [
        .unsupportedPlatform: Entry(keySuffix: "unsupported_platform", systemImage: "desktopcomputer"),
        .disabledBySetting: Entry(keySuffix: "disabled_by_setting", systemImage: "location.slash"),
        .authorizationRestricted: Entry(keySuffix: "authorization_restricted", systemImage: "lock"),
        .authorizationDenied: Entry(keySuffix: "authorization_denied", systemImage: "location.slash"),
        .authorizationNotDetermined: Entry(keySuffix: "authorization_not_determined", systemImage: "questionmark.circle"),
        .backgroundWithoutAlwaysAuthorization: Entry(keySuffix: "background_without_always", systemImage: "location.circle"),
        .locationUnavailable: Entry(keySuffix: "location_unavailable", systemImage: "location.slash.circle"),
        .noFixesReceived: Entry(keySuffix: "no_fixes_received", systemImage: "antenna.radiowaves.left.and.right.slash"),
        .allFixesInaccurate: Entry(keySuffix: "all_fixes_inaccurate", systemImage: "scope"),
        .notRecorded: Entry(keySuffix: "not_recorded", systemImage: "map"),
        .notInCloud: Entry(keySuffix: "not_in_cloud", systemImage: "icloud.slash")
    ]

    /// 表にない理由に使う代わりの項目です(表はすべての理由を含むので、通常は使いません)。
    private static let fallbackEntry = Entry(keySuffix: "not_recorded", systemImage: "map")

    /// 描けない理由を、出す内容(キーと記号)へ写します。
    ///
    /// 責務: 理由ごとに `history.route.absence.*` のキーと SF Symbols の名前を選びます。
    /// - Parameter reason: 描けない理由。
    /// - Returns: 理由の文言キーと記号。
    func absence(_ reason: DrivingRouteAbsenceReason) -> DrivingRouteUnavailableContent {
        let entry = Self.entry(for: reason)
        return DrivingRouteUnavailableContent(messageKey: "history.route.absence.\(entry.keySuffix)", systemImage: entry.systemImage)
    }

    /// 注記をローカライズキーへ写します。
    ///
    /// 責務: 注記の種類ごとに `history.route.notice.*` のキーを選びます。部分の注記は理由ごとに分けます。
    /// - Parameter notice: 注記。
    /// - Returns: 注記の文言キー。
    func notice(_ notice: DrivingRouteNotice) -> String {
        switch notice {
        case .partiallyRecorded(let reason): "history.route.notice.partial.\(Self.entry(for: reason).keySuffix)"
        case .reducedAccuracy: "history.route.notice.reduced_accuracy"
        case .inaccurateFixesExcluded: "history.route.notice.inaccurate_excluded"
        case .unverifiedRestoredCopy: "history.route.notice.unverified_restore"
        }
    }

    /// 理由の項目を表から引きます。
    ///
    /// 責務: 表にある項目を返し、無ければ代わりの項目を返します。
    /// - Parameter reason: 描けない理由。
    /// - Returns: キーの末尾と記号。
    private static func entry(for reason: DrivingRouteAbsenceReason) -> Entry {
        entries[reason] ?? fallbackEntry
    }
}
