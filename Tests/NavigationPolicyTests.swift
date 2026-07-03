import XCTest
import WebKit

final class NavigationPolicyTests: XCTestCase {
    func testAllowsHttpsAboutBwassetData() {
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "https://api.example.com/x")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "about:blank")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "bwasset://template/logo.png")), .allow)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "data:image/png;base64,AAAA")), .allow)
    }

    func testBlocksFileHttpAndNil() {
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "file:///etc/hosts")), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(for: URL(string: "http://insecure.example.com")), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(for: nil), .cancel)
    }
}
