import XCTest
@testable import VoxFlowTextProcessing

final class UnitNormalizerTests: XCTestCase {
    // MARK: - Length

    func testConvertsLengthUnitsAfterArabicDigits() {
        XCTAssertEqual(UnitNormalizer.process("这条路有5公里长"), "这条路有5km长")
        XCTAssertEqual(UnitNormalizer.process("这条河大约3千米深"), "这条河大约3km深")
        XCTAssertEqual(UnitNormalizer.process("身高180厘米"), "身高180cm")
        XCTAssertEqual(UnitNormalizer.process("身高180公分"), "身高180cm")
        XCTAssertEqual(UnitNormalizer.process("降雨量15毫米"), "降雨量15mm")
        XCTAssertEqual(UnitNormalizer.process("跑道长400米"), "跑道长400m")
    }

    // MARK: - Mass

    func testConvertsMassUnits() {
        XCTAssertEqual(UnitNormalizer.process("重量是25千克"), "重量是25kg")
        XCTAssertEqual(UnitNormalizer.process("买了2公斤苹果"), "买了2kg苹果")
        XCTAssertEqual(UnitNormalizer.process("剂量500毫克"), "剂量500mg")
        XCTAssertEqual(UnitNormalizer.process("糖10克"), "糖10g")
        XCTAssertEqual(UnitNormalizer.process("载重30吨"), "载重30t")
    }

    // MARK: - Temperature

    func testConvertsTemperatureUnits() {
        XCTAssertEqual(UnitNormalizer.process("气温37摄氏度"), "气温37°C")
        XCTAssertEqual(UnitNormalizer.process("室外98华氏度"), "室外98°F")
    }

    // MARK: - Time

    func testConvertsTimeUnits() {
        XCTAssertEqual(UnitNormalizer.process("等了3小时"), "等了3h")
        XCTAssertEqual(UnitNormalizer.process("等了30分钟"), "等了30min")
        XCTAssertEqual(UnitNormalizer.process("耗时120毫秒"), "耗时120ms")
        XCTAssertEqual(UnitNormalizer.process("倒计时10秒"), "倒计时10s")
    }

    // MARK: - Volume / Area / Cubic / Speed

    func testConvertsVolumeAreaCubicAndSpeedUnits() {
        XCTAssertEqual(UnitNormalizer.process("加油50升"), "加油50L")
        XCTAssertEqual(UnitNormalizer.process("药水10毫升"), "药水10mL")
        XCTAssertEqual(UnitNormalizer.process("占地100平方千米"), "占地100km²")
        XCTAssertEqual(UnitNormalizer.process("占地100平方公里"), "占地100km²")
        XCTAssertEqual(UnitNormalizer.process("房间90平方米"), "房间90m²")
        XCTAssertEqual(UnitNormalizer.process("体积15立方米"), "体积15m³")
        XCTAssertEqual(UnitNormalizer.process("时速60公里每小时"), "时速60km/h")
    }

    // MARK: - Longest-match first

    func testLongestMatchWins() {
        // 千米 must match before 米; 平方米 before 米; 千克 before 克.
        XCTAssertEqual(UnitNormalizer.process("3千米"), "3km")
        XCTAssertEqual(UnitNormalizer.process("90平方米"), "90m²")
        XCTAssertEqual(UnitNormalizer.process("25千克"), "25kg")
    }

    // MARK: - No digit prefix → unchanged (ambiguity guard)

    func testDoesNotConvertWithoutDigitPrefix() {
        // 大米/玉米/立方米 worker… no digit → no conversion. Ambiguous nouns stay.
        XCTAssertEqual(UnitNormalizer.process("今天吃了大米"), "今天吃了大米")
        XCTAssertEqual(UnitNormalizer.process("十分满意"), "十分满意")
        XCTAssertEqual(UnitNormalizer.process("秒杀活动"), "秒杀活动")
        XCTAssertEqual(UnitNormalizer.process("步步高升"), "步步高升")
    }

    func testDoesNotConvertPrefixesOfOtherUnitsOrWords() {
        XCTAssertEqual(UnitNormalizer.process("钻石5克拉"), "钻石5克拉")
        XCTAssertEqual(UnitNormalizer.process("买3米其林轮胎"), "买3米其林轮胎")
    }

    func testConvertsUnitsBeforeSeparateChineseWords() {
        XCTAssertEqual(UnitNormalizer.process("5公里"), "5km")
        XCTAssertEqual(UnitNormalizer.process("5公里左右"), "5km左右")
    }

    // MARK: - Chinese numerals are not converted here (smartNumber handles them)

    func testChineseNumeralsStayUntouched() {
        // "五公里" is handled by smartNumberRecognition (五→5) running before
        // unit normalization; without a digit prefix the unit stays Chinese.
        XCTAssertEqual(UnitNormalizer.process("五公里"), "五公里")
    }

    // MARK: - Protected regions

    func testProtectedRegionsAreUntouched() {
        XCTAssertEqual(UnitNormalizer.process("参考`5公里`配置"), "参考`5公里`配置")
        XCTAssertEqual(UnitNormalizer.process("见 https://example.com/5公里/page"), "见 https://example.com/5公里/page")
        XCTAssertEqual(UnitNormalizer.process("2.5公里左右"), "2.5公里左右")
    }

    // MARK: - Multiple conversions in one pass

    func testConvertsMultipleOccurrences() {
        XCTAssertEqual(UnitNormalizer.process("长5公里宽3米"), "长5km宽3m")
    }
}
