import SwiftUI

/// Colors from the two "Noble Highlands" schemes (schemecolor.com).
enum Theme {
    // Scheme 1
    static let red = Color(hex: 0x7F3939)
    static let orange = Color(hex: 0xCB7819)
    static let teal = Color(hex: 0x228686)
    static let charcoal = Color(hex: 0x282828)
    // Scheme 2
    static let green = Color(hex: 0x759A60)
    static let navy = Color(hex: 0x2C4268)
    static let blue = Color(hex: 0x3C5A8E)
    static let ink = Color(hex: 0x0E1520)

    /// Not in either scheme: `ink` at half brightness, darker than the tiles but not black.
    static let background = Color(hex: 0x070B10)
    static let tile = ink
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
