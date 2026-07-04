import XCTest

final class PrivateHostTests: XCTestCase {

    func testLoopbackAndRFC1918ArePrivate() {
        for host in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255",
                     "192.168.1.114", "169.254.1.1"] {
            XCTAssertTrue(PrivateHost.isPrivate(host), "\(host) should be private")
        }
    }

    func testTailscaleCGNATIsPrivate() {
        // 100.64.0.0/10 — the range Tailscale hands out (homeserver = 100.100.100.100).
        for host in ["100.64.0.1", "100.100.100.100", "100.127.255.255"] {
            XCTAssertTrue(PrivateHost.isPrivate(host), "\(host) should be private")
        }
    }

    func testRangeBoundariesAreNotPrivate() {
        // Just outside each private block must fall back to public (HTTPS-only).
        for host in ["172.15.255.255", "172.32.0.1", "192.169.0.1",
                     "100.63.255.255", "100.128.0.1", "11.0.0.1"] {
            XCTAssertFalse(PrivateHost.isPrivate(host), "\(host) should be public")
        }
    }

    func testPublicIPv4IsNotPrivate() {
        for host in ["8.8.8.8", "1.2.3.4", "93.184.216.34"] {
            XCTAssertFalse(PrivateHost.isPrivate(host), "\(host) should be public")
        }
    }

    func testHostnames() {
        XCTAssertTrue(PrivateHost.isPrivate("localhost"))
        XCTAssertTrue(PrivateHost.isPrivate("LOCALHOST"))
        XCTAssertTrue(PrivateHost.isPrivate("homeserver.local"))
        XCTAssertTrue(PrivateHost.isPrivate("foo.LOCAL"))
        XCTAssertFalse(PrivateHost.isPrivate("example.com"))
        XCTAssertFalse(PrivateHost.isPrivate("localhost.evil.com"))
    }

    func testEmptyAndNil() {
        XCTAssertFalse(PrivateHost.isPrivate(nil))
        XCTAssertFalse(PrivateHost.isPrivate(""))
    }

    func testIPv6() {
        XCTAssertTrue(PrivateHost.isPrivate("::1"))              // loopback
        XCTAssertTrue(PrivateHost.isPrivate("fc00::1"))         // ULA
        XCTAssertTrue(PrivateHost.isPrivate("fd7a:115c:a1e0::1")) // Tailscale ULA
        XCTAssertTrue(PrivateHost.isPrivate("fe80::1"))         // link-local
        XCTAssertFalse(PrivateHost.isPrivate("2001:4860:4860::8888")) // public
    }
}
