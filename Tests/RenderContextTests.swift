import XCTest

final class RenderContextTests: XCTestCase {
    private func bw(slide: Int?) throws -> [String: Any] {
        let ctx = RenderContext(params: [:], data: [:], size: .large, theme: .light, stale: false, slide: slide)
        let data = try ctx.bwJSON().data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testSlideInjectedWhenSet() throws {
        XCTAssertEqual(try bw(slide: 2)["slide"] as? Int, 2)
    }

    func testSlideAbsentWhenNil() throws {
        XCTAssertNil(try bw(slide: nil)["slide"])
    }
}
