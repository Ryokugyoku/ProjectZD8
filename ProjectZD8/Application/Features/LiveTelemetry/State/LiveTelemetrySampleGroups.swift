/// 取得済みPIDサンプルを、主要値・車種専用値・分類ごとの値へ振り分けた表示用のまとまりです。
///
/// iOSとmacOSで共通の判定です。どの一覧も取得順を保ちます。
struct LiveTelemetrySampleGroups: Equatable {
    /// 主要値として優先する要求です。回転数(01 0C)、車速(01 0D)の順です。
    private static let preferredPrimaryRequests = [
        OBDPIDRequest(service: 0x01, pid: 0x0C),
        OBDPIDRequest(service: 0x01, pid: 0x0D),
    ]
    /// 主要値の最大件数です。
    private static let primaryLimit = 2

    /// 振り分け元の取得順のサンプルです。
    let samples: [OBDPIDSample]
    /// 主要値です。回転数・車速を先に置き、残りを取得順で補った最大2件で、重複を含みません。
    let primarySamples: [OBDPIDSample]
    /// 型式コードを持つ車種専用のサンプルです。取得順を保ちます。
    let vehicleSpecificSamples: [OBDPIDSample]
    /// 車種専用サンプルの先頭が持つ型式コードです。車種専用サンプルがなければ `nil` です。
    let vehicleSpecificModelCode: String?
    /// サンプルが1件以上ある分類です。`OBDPIDCategory.allCases` の順です。
    let availableCategories: [OBDPIDCategory]

    /// 取得済みサンプルから表示用のまとまりを生成します。
    ///
    /// 責務: 1回分の取得済みサンプルを主要値・車種専用値・分類へ振り分けます。
    /// - Parameter samples: 取得順のPIDサンプル。
    init(samples: [OBDPIDSample]) {
        self.samples = samples
        primarySamples = Self.primarySamples(from: samples)
        vehicleSpecificSamples = samples.filter(Self.isVehicleSpecific)
        vehicleSpecificModelCode = vehicleSpecificSamples.first?.vehicleModelCode
        availableCategories = OBDPIDCategory.allCases.filter { category in
            samples.contains { OBDPIDCategory.category(for: $0.request) == category }
        }
    }

    /// 指定した分類のサンプルを返します。
    ///
    /// 責務: 全サンプルから1件の分類に属するものだけを取得順のまま取り出します。
    /// - Parameter category: 取り出すPID分類。
    /// - Returns: 分類内のサンプル。該当がなければ空配列。
    func samples(in category: OBDPIDCategory) -> [OBDPIDSample] {
        samples.filter { OBDPIDCategory.category(for: $0.request) == category }
    }

    /// 分類の代表値を返します。
    ///
    /// 責務: 分類内のサンプルから、分類が定める代表PIDを優先して1件を選びます。
    /// - Parameter category: 代表値を選ぶPID分類。
    /// - Returns: 代表PIDのサンプル。なければ分類内の先頭。分類が空なら `nil`。
    func representativeSample(in category: OBDPIDCategory) -> OBDPIDSample? {
        let values = samples(in: category)
        return values.first { $0.request == category.representativeRequest } ?? values.first
    }

    /// 選択中の分類を、表示できる分類へ補正します。
    ///
    /// 責務: 選択中の分類がサンプルを持たなくなった時に、表示できる先頭の分類へ置き換えます。
    /// - Parameter selected: 現在選択している分類。
    /// - Returns: 選択中の分類が表示できればそのまま。できなければ先頭の分類。表示できる分類がなければ `selected`。
    func resolvedCategory(_ selected: OBDPIDCategory) -> OBDPIDCategory {
        if availableCategories.contains(selected) { return selected }
        return availableCategories.first ?? selected
    }

    /// サンプルが車種専用かどうかを判定します。
    ///
    /// 責務: 型式コードが `nil` でも空文字でもないサンプルだけを車種専用と判定します。
    /// - Parameter sample: 判定するPIDサンプル。
    /// - Returns: 車種専用なら `true`。
    static func isVehicleSpecific(_ sample: OBDPIDSample) -> Bool {
        guard let code = sample.vehicleModelCode else { return false }
        return !code.isEmpty
    }

    /// 主要値を選びます。
    ///
    /// 責務: 回転数・車速を優先し、残りを取得順で補って重複のない最大2件を返します。
    /// - Parameter samples: 取得順のPIDサンプル。
    /// - Returns: 主要値として表示するサンプル。
    private static func primarySamples(from samples: [OBDPIDSample]) -> [OBDPIDSample] {
        let preferred = preferredPrimaryRequests.compactMap { request in
            samples.first { $0.request == request }
        }
        let preferredRequests = Set(preferred.map(\.request))
        let others = samples.filter { !preferredRequests.contains($0.request) }
        return Array((preferred + others).prefix(primaryLimit))
    }
}
