import SwiftUI
import AppKit

/// Shared visual language (editorial minimal): warm monochrome + a single orange accent.
/// Single source of truth for 3a/3b/3c so screens stay consistent.
enum DesignTokens {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static let background = adaptive(light: hex(0xFAF8F4), dark: hex(0x16130E))
    static let surface    = adaptive(light: hex(0xFFFFFF), dark: hex(0x201C16))
    static let textPrimary   = adaptive(light: hex(0x1A1A1A), dark: hex(0xF0ECE4))
    static let textSecondary = adaptive(light: hex(0x6B6560), dark: hex(0xA8A199))
    static let separator = adaptive(light: NSColor.black.withAlphaComponent(0.10),
                                    dark: NSColor.white.withAlphaComponent(0.12))
    static let accent     = adaptive(light: hex(0xE8590C), dark: hex(0xFF7A33))
    static let statusOK    = adaptive(light: hex(0x2F9E44), dark: hex(0x51CF66))
    static let statusStale = adaptive(light: hex(0xF08C00), dark: hex(0xFFA94D))
    static let statusError = adaptive(light: hex(0xE03131), dark: hex(0xFF6B6B))

    static func statusColor(_ status: InstanceStatus) -> Color {
        switch status {
        case .ok: return statusOK
        case .stale: return statusStale
        case .error: return statusError
        }
    }

    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 40, section: CGFloat = 80
    }

    enum FontSize {
        static let caption: CGFloat = 11, label: CGFloat = 13, title: CGFloat = 18, titleXL: CGFloat = 28
    }
}
