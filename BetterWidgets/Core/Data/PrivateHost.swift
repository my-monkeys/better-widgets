import Foundation
import Network

/// Decides whether a host sits on a private/local network, where plaintext HTTP
/// is acceptable (home servers, LAN dashboards, Tailscale tailnets). Public hosts
/// must still use HTTPS — this never green-lights cleartext to the internet.
/// Recognizes loopback, RFC1918, link-local and CGNAT (100.64/10, used by
/// Tailscale) IP literals, plus `localhost` and mDNS `.local` hostnames.
enum PrivateHost {
    static func isPrivate(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") { return true }
        if let v4 = IPv4Address(host) { return isPrivateV4(v4.rawValue) }
        if let v6 = IPv6Address(host) { return isPrivateV6(v6.rawValue) }
        return false
    }

    private static func isPrivateV4(_ raw: Data) -> Bool {
        guard raw.count == 4 else { return false }
        let b = [UInt8](raw)
        switch b[0] {
        case 127: return true                       // 127.0.0.0/8   loopback
        case 10: return true                        // 10.0.0.0/8    RFC1918
        case 172: return (16...31).contains(b[1])   // 172.16.0.0/12 RFC1918
        case 192: return b[1] == 168                // 192.168.0.0/16 RFC1918
        case 169: return b[1] == 254                // 169.254.0.0/16 link-local
        case 100: return (64...127).contains(b[1])  // 100.64.0.0/10 CGNAT (Tailscale)
        default: return false
        }
    }

    private static func isPrivateV6(_ raw: Data) -> Bool {
        guard raw.count == 16 else { return false }
        let b = [UInt8](raw)
        if b[0...14].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true } // ::1 loopback
        if (b[0] & 0xFE) == 0xFC { return true }                          // fc00::/7 ULA (Tailscale)
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }          // fe80::/10 link-local
        return false
    }
}
