import Observation
import SwiftUI
import UIKit

public enum Palette {
    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? hex(dark, alpha: darkAlpha) : hex(light, alpha: lightAlpha)
        })
    }

    public static let seaBlue = dynamic(light: 0x3E7C8C, dark: 0x5FA3B3)
    public static let sage = dynamic(light: 0x7F9D84, dark: 0x93B29A)
    public static let coral = dynamic(light: 0xE07B63, dark: 0xEE937B)
    public static let sand = dynamic(light: 0xD9C29A, dark: 0xE3CFA8)
    public static let mist = dynamic(light: 0xA9BCC0, dark: 0x6E8489)
    public static let deep1 = dynamic(light: 0xDCEFF0, dark: 0x071821)
    public static let ink = dynamic(light: 0x12313A, dark: 0xEAF2F0)
    public static let inkSecondary = dynamic(light: 0x4A6A72, dark: 0x9DB4B8)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x0E2D39, lightAlpha: 0.58, darkAlpha: 0.62)
    public static let hairline = dynamic(light: 0x12313A, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)

    public static func color(token: String) -> Color {
        switch token {
        case "seaBlue": seaBlue
        case "sage": sage
        case "coral": coral
        case "sand": sand
        case "mist": mist
        default: mist
        }
    }
}

public enum KinetFont {
    public static let pageTitle: Font = .largeTitle.weight(.bold)
    public static let balance: Font = .system(size: 44, weight: .bold, design: .rounded)
    public static let timer: Font = .system(size: 72, weight: .light, design: .rounded)
    public static let metric: Font = .system(.title2, design: .rounded, weight: .semibold)
    public static let caption: Font = .footnote
    public static let eyebrow: Font = .system(.caption, design: .rounded, weight: .semibold)
}

@MainActor
@Observable
public final class PageTracker {
    public var position: Double = 1
    public var profileAtTop = true

    public init() {}

    public func updateProfileTop(_ value: Bool) {
        guard value != profileAtTop else { return }
        profileAtTop = value
    }

    public func update(_ value: Double) {
        guard abs(value - position) > 0.0001 else { return }
        position = value
    }
}

public extension EnvironmentValues {
    @Entry var pageBottomInset: CGFloat = 0
    @Entry var pageActive: Bool = true
    @Entry var screenInsets: EdgeInsets = EdgeInsets()
}
