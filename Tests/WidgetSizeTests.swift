import XCTest
// No module import: Core sources are compiled directly into the test target.

/// Regression lock for the reload↔display `kind` seam: RenderPipeline derives the WidgetKit
/// `kind` from `WidgetSize.kind`, while WidgetExtension/WidgetBundle.swift now reads
/// `WidgetSize.<case>.kind` directly instead of repeating the string literals. Either way, if
/// this format ever changes, this test catches it before placed widgets silently stop updating.
final class WidgetSizeTests: XCTestCase {
    func testWidgetSizeKindStringsAreStable() {
        XCTAssertEqual(WidgetSize.small.kind, "bw.small")
        XCTAssertEqual(WidgetSize.medium.kind, "bw.medium")
        XCTAssertEqual(WidgetSize.large.kind, "bw.large")
    }
}
