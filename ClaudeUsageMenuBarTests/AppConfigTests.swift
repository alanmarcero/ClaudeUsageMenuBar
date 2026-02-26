import XCTest
import SwiftUI
@testable import ClaudeUsageMenuBar

final class AppConfigTests: XCTestCase {

    func testColorForPercentageNil() {
        let color = AppConfig.shared.colorForPercentage(nil)
        XCTAssertEqual(color, .secondary)
    }

    func testColorForPercentageGreen() {
        XCTAssertEqual(AppConfig.shared.colorForPercentage(0), .green)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(30), .green)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(54), .green)
    }

    func testColorForPercentageYellow() {
        XCTAssertEqual(AppConfig.shared.colorForPercentage(55), .orange)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(70), .orange)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(84), .orange)
    }

    func testColorForPercentageRed() {
        XCTAssertEqual(AppConfig.shared.colorForPercentage(85), .red)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(90), .red)
        XCTAssertEqual(AppConfig.shared.colorForPercentage(100), .red)
    }

    func testGradientColorsGreen() {
        let colors = AppConfig.shared.gradientColors(for: 30)
        XCTAssertEqual(colors, [.green, .mint])
    }

    func testGradientColorsYellow() {
        let colors = AppConfig.shared.gradientColors(for: 70)
        XCTAssertEqual(colors, [.orange, .yellow])
    }

    func testGradientColorsRed() {
        let colors = AppConfig.shared.gradientColors(for: 90)
        XCTAssertEqual(colors, [.red, .orange])
    }

    func testDefaultThresholds() {
        XCTAssertEqual(AppConfig.shared.yellowThreshold, 55)
        XCTAssertEqual(AppConfig.shared.redThreshold, 85)
    }
}
