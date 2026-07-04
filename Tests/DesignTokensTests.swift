import XCTest
import SwiftUI

final class DesignTokensTests: XCTestCase {
    func testSpacingScaleIsMonotonic() {
        let scale = [DesignTokens.Space.xs, DesignTokens.Space.sm, DesignTokens.Space.md,
                     DesignTokens.Space.lg, DesignTokens.Space.xl, DesignTokens.Space.xxl,
                     DesignTokens.Space.section]
        XCTAssertEqual(scale, scale.sorted(), "spacing scale must increase")
        XCTAssertEqual(DesignTokens.Space.lg, 16)
    }

    func testTypeScaleHasDistinctSizes() {
        let sizes = Set([DesignTokens.FontSize.caption, DesignTokens.FontSize.label,
                         DesignTokens.FontSize.title, DesignTokens.FontSize.titleXL])
        XCTAssertEqual(sizes.count, 4, "≥ 3 distinct type sizes required")
        XCTAssertGreaterThan(DesignTokens.FontSize.titleXL, DesignTokens.FontSize.title)
    }

    func testAccentIsDefined() {
        XCTAssertNotNil(DesignTokens.accent)
    }
}
