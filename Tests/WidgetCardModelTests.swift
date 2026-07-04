import XCTest

final class WidgetCardModelTests: XCTestCase {
    private func model(_ status: InstanceStatus, size: WidgetSize = .small) -> WidgetCardModel {
        let inst = WidgetInstance(id: UUID(), name: "T", templateId: "x", size: size, paramValues: [:])
        return WidgetCardModel(instance: inst, status: status,
                               rendersDir: { id, theme in
                                   URL(fileURLWithPath: "/tmp/\(id.uuidString)-\(theme.rawValue).png")
                               })
    }

    func testImageURLByTheme() {
        let m = model(.ok)
        XCTAssertTrue(m.imageURL(dark: false).lastPathComponent.hasSuffix("-light.png"))
        XCTAssertTrue(m.imageURL(dark: true).lastPathComponent.hasSuffix("-dark.png"))
    }

    func testStatusLabels() {
        XCTAssertEqual(model(.ok).statusLabel, "À jour")
        XCTAssertEqual(model(.stale).statusLabel, "Données périmées")
        XCTAssertEqual(model(.error("x")).statusLabel, "Erreur")
    }

    func testCardWidthBySize() {
        XCTAssertEqual(model(.ok, size: .small).cardWidth, 170)
        XCTAssertEqual(model(.ok, size: .medium).cardWidth, 340)
        XCTAssertEqual(model(.ok, size: .large).cardWidth, 340)
    }
}
