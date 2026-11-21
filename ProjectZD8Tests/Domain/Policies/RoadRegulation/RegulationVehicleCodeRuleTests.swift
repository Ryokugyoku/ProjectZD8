import XCTest
@testable import ProjectZD8

/// `RegulationVehicleCodeRule` が、対象車両コード(A〜D)を普通乗用車・軽乗用車の立場で3値に判定することを検証します。
final class RegulationVehicleCodeRuleTests: XCTestCase {
    private let standard = RegulationVehicleCodeRule(vehicleClass: .standardPassenger)
    private let kei = RegulationVehicleCodeRule(vehicleClass: .keiPassenger)

    /// 責務: 0 を並べた桁の位置(右から数えて何桁目か)に 1 を立てたコードを返します。
    private func digit(_ position: Int) -> String {
        "1" + String(repeating: "0", count: position - 1)
    }

    /// 責務: 車両コードだけを持つ条件の組を作ります。
    private func set(a: String? = nil, b: String? = nil, c: String? = nil, d: String? = nil) -> RoadRegulationConditionSet {
        RoadRegulationConditionSet(vehicleCodeA: a, vehicleCodeB: b, vehicleCodeC: c, vehicleCodeD: d)
    }

    /// 責務: A の 1(車両)・2(自動車)・3(乗用)・4(普乗)・5(普通)の桁が、普通乗用車に当てはまることを確かめます。
    func testCategoryADigitsOneToFiveApply() {
        for position in 1...5 {
            XCTAssertEqual(standard.evaluateTarget(set(a: digit(position))), .applies, "A の \(position) 桁目")
            XCTAssertEqual(kei.evaluateTarget(set(a: digit(position))), .applies, "軽 A の \(position) 桁目")
        }
    }

    /// 責務: A の中型・大型系・タクシー・標章車などの桁が、普通乗用車に当てはまらないことを確かめます。
    func testCategoryAOtherDigitsDoNotApply() {
        for position in [6, 7, 8, 9, 11, 12, 13, 14] {
            XCTAssertEqual(standard.evaluateTarget(set(a: digit(position))), .doesNotApply, "A の \(position) 桁目")
            XCTAssertEqual(kei.evaluateTarget(set(a: digit(position))), .doesNotApply, "軽 A の \(position) 桁目")
        }
    }

    /// 責務: A の軽(10桁目)が、普通乗用車では当てはまらず、軽乗用車では当てはまることを確かめます。
    func testKeiDigitDependsOnVehicleClass() {
        XCTAssertEqual(standard.evaluateTarget(set(a: "1000000000")), .doesNotApply)
        XCTAssertEqual(kei.evaluateTarget(set(a: "1000000000")), .applies)
    }

    /// 責務: A の15桁目(タイヤチェーン)だけがある時に不明になることを確かめます。
    func testTireChainDigitAloneIsUnknown() {
        XCTAssertEqual(standard.evaluateTarget(set(a: digit(15))), .unknown)
        XCTAssertEqual(kei.evaluateTarget(set(a: digit(15))), .unknown)
    }

    /// 責務: B・C(大型・貨物系)だけの指定が当てはまらないことを確かめます。
    func testCategoriesBAndCDoNotApply() {
        XCTAssertEqual(standard.evaluateTarget(set(b: "1")), .doesNotApply)
        XCTAssertEqual(standard.evaluateTarget(set(c: "1")), .doesNotApply)
        XCTAssertEqual(standard.evaluateTarget(set(b: "11", c: "10")), .doesNotApply)
    }

    /// 責務: D(その他)の指定は、15桁目だけなら不明、それ以外の桁だけなら当てはまらないことを確かめます。
    func testCategoryDOtherDigitIsUnknownOnlyForFifteenth() {
        XCTAssertEqual(standard.evaluateTarget(set(d: "1000")), .doesNotApply)
        XCTAssertEqual(standard.evaluateTarget(set(d: digit(15))), .unknown)
    }

    /// 責務: 複数カテゴリの組み合わせで、当てはまるものがあれば当てはまり、次いで不明が優先されることを確かめます。
    func testCategoriesCombineAsOr() {
        XCTAssertEqual(standard.evaluateTarget(set(a: "1", d: digit(15))), .applies)
        XCTAssertEqual(standard.evaluateTarget(set(a: "1", b: "1")), .applies)
        XCTAssertEqual(standard.evaluateTarget(set(a: digit(15), b: "1")), .unknown)
        XCTAssertEqual(standard.evaluateTarget(set(a: digit(6), b: "1", c: "1", d: "1000")), .doesNotApply)
    }

    /// 責務: 0/1 以外の文字や16桁以上のコードが不明になることを確かめます。
    func testMalformedCodesAreUnknown() {
        XCTAssertEqual(standard.evaluateTarget(set(a: "2")), .unknown)
        XCTAssertEqual(standard.evaluateTarget(set(a: "abc")), .unknown)
        XCTAssertEqual(standard.evaluateTarget(set(a: digit(16))), .unknown)
        XCTAssertEqual(standard.evaluateTarget(set(b: "12")), .unknown)
        XCTAssertEqual(standard.evaluateTarget(set(d: "1x")), .unknown)
    }

    /// 責務: 立っている桁が無いコード("0")が、当てはまらない(不明ではない)ことを確かめます。
    func testZeroCodeDoesNotApply() {
        XCTAssertEqual(standard.evaluateTarget(set(a: "0")), .doesNotApply)
        XCTAssertEqual(standard.evaluateExclusion(set(a: "0")), .doesNotApply)
    }

    /// 責務: 除外の A の15桁目(タイヤチェーン)が、対象と同じく不明になることを確かめます。
    func testExclusionTireChainIsUnknownForBothClasses() {
        XCTAssertEqual(kei.evaluateExclusion(set(a: digit(15))), .unknown)
    }

    /// 責務: 車両コードがすべて空の対象は、車両の制約なしとして当てはまることを確かめます。
    func testEmptyTargetApplies() {
        XCTAssertEqual(standard.evaluateTarget(.empty), .applies)
        XCTAssertEqual(kei.evaluateTarget(.empty), .applies)
    }

    /// 責務: 除外の車両も同じ規則(普乗は当てはまる、B は当てはまらない、軽は車種で変わる)で判定されることを確かめます。
    func testExclusionUsesSameRules() {
        XCTAssertEqual(standard.evaluateExclusion(set(a: "1000")), .applies)
        XCTAssertEqual(standard.evaluateExclusion(set(b: "1")), .doesNotApply)
        XCTAssertEqual(standard.evaluateExclusion(set(a: "1000000000")), .doesNotApply)
        XCTAssertEqual(kei.evaluateExclusion(set(a: "1000000000")), .applies)
        XCTAssertEqual(standard.evaluateExclusion(set(a: "2")), .unknown)
    }

    /// 責務: 除外の「その他」(D の15桁目)は、除外しない(当てはまらない)とみなされることを確かめます。
    func testExclusionOtherIsTreatedAsNotExcluded() {
        XCTAssertEqual(standard.evaluateExclusion(set(d: digit(15))), .doesNotApply)
        XCTAssertEqual(kei.evaluateExclusion(set(d: digit(15))), .doesNotApply)
        XCTAssertEqual(standard.evaluateExclusion(set(a: digit(15))), .unknown)
    }
}
