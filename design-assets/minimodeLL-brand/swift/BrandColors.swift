import SwiftUI

/// Brand palette. Adaptive colors come from the asset catalog (light/dark aware).
public extension Color {
    static let mmInk      = Color("BrandInk")      // #16181D / #F2F3EF
    static let mmSurface  = Color("BrandSurface")  // #F2F3EF / #16181D
    static let mmMuted    = Color("BrandMuted")    // #5B5F68 / #A3A7AF
    static let mmAccent   = Color("AccentColor")   // #3A5BD9 / #7D96FF

    static let mmRunning  = Color(red: 0x1F/255, green: 0x8A/255, blue: 0x5B/255)
    static let mmWarning  = Color(red: 0xB7/255, green: 0x79/255, blue: 0x1F/255)
    static let mmBlocked  = Color(red: 0xC2/255, green: 0x3B/255, blue: 0x3B/255)
}
