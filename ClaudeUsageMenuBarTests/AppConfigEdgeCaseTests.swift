import XCTest
import SwiftUI
@testable import ClaudeUsageMenuBar

final class AppConfigEdgeCaseTests: XCTestCase {

    // MARK: - Color Threshold Edge Cases

    func testColorAtExactYellowThreshold() {
        // At exactly 55%, should be orange (yellow threshold)
        let color = AppConfig.shared.colorForPercentage(55)
        XCTAssertEqual(color, .orange)
    }

    func testColorJustBelowYellowThreshold() {
        // At 54%, should still be green
        let color = AppConfig.shared.colorForPercentage(54)
        XCTAssertEqual(color, .green)
    }

    func testColorAtExactRedThreshold() {
        // At exactly 85%, should be red
        let color = AppConfig.shared.colorForPercentage(85)
        XCTAssertEqual(color, .red)
    }

    func testColorJustBelowRedThreshold() {
        // At 84%, should still be orange
        let color = AppConfig.shared.colorForPercentage(84)
        XCTAssertEqual(color, .orange)
    }

    func testColorAtZeroPercent() {
        let color = AppConfig.shared.colorForPercentage(0)
        XCTAssertEqual(color, .green)
    }

    func testColorAt100Percent() {
        let color = AppConfig.shared.colorForPercentage(100)
        XCTAssertEqual(color, .red)
    }

    func testColorAbove100Percent() {
        // Edge case: percentage over 100
        let color = AppConfig.shared.colorForPercentage(150)
        XCTAssertEqual(color, .red)
    }

    func testColorNegativePercent() {
        // Edge case: negative percentage (should be green as below all thresholds)
        let color = AppConfig.shared.colorForPercentage(-10)
        XCTAssertEqual(color, .green)
    }

    // MARK: - Gradient Color Edge Cases

    func testGradientAtExactYellowThreshold() {
        let colors = AppConfig.shared.gradientColors(for: 55)
        XCTAssertEqual(colors, [.orange, .yellow])
    }

    func testGradientJustBelowYellowThreshold() {
        let colors = AppConfig.shared.gradientColors(for: 54)
        XCTAssertEqual(colors, [.green, .mint])
    }

    func testGradientAtExactRedThreshold() {
        let colors = AppConfig.shared.gradientColors(for: 85)
        XCTAssertEqual(colors, [.red, .orange])
    }

    func testGradientJustBelowRedThreshold() {
        let colors = AppConfig.shared.gradientColors(for: 84)
        XCTAssertEqual(colors, [.orange, .yellow])
    }

    func testGradientAtZero() {
        let colors = AppConfig.shared.gradientColors(for: 0)
        XCTAssertEqual(colors, [.green, .mint])
    }

    func testGradientAt100() {
        let colors = AppConfig.shared.gradientColors(for: 100)
        XCTAssertEqual(colors, [.red, .orange])
    }

    // MARK: - Threshold Range Tests

    func testGreenRangeCoversZeroTo54() {
        for percentage in 0..<55 {
            let color = AppConfig.shared.colorForPercentage(percentage)
            XCTAssertEqual(color, .green, "Expected green at \(percentage)%")
        }
    }

    func testOrangeRangeCovers55To84() {
        for percentage in 55..<85 {
            let color = AppConfig.shared.colorForPercentage(percentage)
            XCTAssertEqual(color, .orange, "Expected orange at \(percentage)%")
        }
    }

    func testRedRangeCovers85AndAbove() {
        for percentage in 85...100 {
            let color = AppConfig.shared.colorForPercentage(percentage)
            XCTAssertEqual(color, .red, "Expected red at \(percentage)%")
        }
    }
}
