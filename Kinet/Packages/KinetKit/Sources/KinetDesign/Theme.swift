import SwiftUI

public struct ThemeColors: Sendable {
    public let top: Color
    public let mid: Color
    public let bottom: Color
    public let floor: Color

    public static func resolve(_ id: String, dark: Bool) -> ThemeColors {
        func c(_ v: UInt32) -> Color {
            Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
        switch (id, dark) {
        case ("coralReef", true): return ThemeColors(top: c(0x1C1712), mid: c(0x3B2F22), bottom: c(0x5C4731), floor: c(0x7C6247))
        case ("coralReef", false): return ThemeColors(top: c(0xF4EADA), mid: c(0xE8D4B0), bottom: c(0xD6BB8C), floor: c(0xEAD4AA))
        case ("polarDeep", true): return ThemeColors(top: c(0x050E1A), mid: c(0x0A1B2E), bottom: c(0x16314F), floor: c(0x2A4560))
        case ("polarDeep", false): return ThemeColors(top: c(0xE8F1F7), mid: c(0xBFD8EA), bottom: c(0x8DB5D6), floor: c(0xC9DCE9))
        case ("bioluminescence", true): return ThemeColors(top: c(0x070A1C), mid: c(0x120F2E), bottom: c(0x24184A), floor: c(0x3A2B66))
        case ("bioluminescence", false): return ThemeColors(top: c(0xE3E2F5), mid: c(0xBDB5E3), bottom: c(0x8E83CC), floor: c(0xCFC6EE))
        case (_, true): return ThemeColors(top: c(0x071821), mid: c(0x0C2733), bottom: c(0x123A47), floor: c(0x2C5560))
        default: return ThemeColors(top: c(0xDCEFF0), mid: c(0xA9D6DA), bottom: c(0x6FB2BC), floor: c(0xE3D3B0))
        }
    }
}

public struct AppTheme: Equatable, Sendable {
    public var themeID: String
    public var skinID: String
    public var accent: Color
    public var water: Color

    public static let standard = AppTheme.make(skinID: "coralSkin", themeID: "lagoon")

    public static func make(skinID: String, themeID: String) -> AppTheme {
        let water: Color
        switch themeID {
        case "coralReef": water = Color(red: 0.82, green: 0.64, blue: 0.40)
        case "polarDeep": water = Color(red: 0.5, green: 0.72, blue: 0.9)
        case "bioluminescence": water = Color(red: 0.55, green: 0.5, blue: 0.9)
        default: water = Palette.seaBlue
        }
        return AppTheme(themeID: themeID, skinID: skinID, accent: water, water: water)
    }
}

public extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .standard
}
