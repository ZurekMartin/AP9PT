import SwiftUI

public struct SheetHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let symbol: String?
    private let tint: Color
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Palette.coral, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(tint.opacity(0.14), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Palette.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension SheetHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Palette.coral) {
        self.init(title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

public struct SheetHint: View {
    @Environment(\.appTheme) private var theme
    private let text: String
    private let isAlert: Bool

    public init(_ text: String, isAlert: Bool = false) {
        self.text = text
        self.isAlert = isAlert
    }

    public var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(isAlert ? theme.accent : Palette.inkSecondary)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct SheetDivider: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

public enum KinetLayout {
    public static let pageMargin: CGFloat = 22
    public static let barHeight: CGFloat = 58
}

public extension View {
    func glassSheetBackground() -> some View {
        presentationBackground { ThemedSheetBackground() }
    }
}

public enum SheetMetrics {
    public static let horizontal: CGFloat = 24
    public static let top: CGFloat = 30
    public static let bottom: CGFloat = 20
    public static let spacing: CGFloat = 22
}

private struct FittedSheetModifier: ViewModifier {
    @State private var height: CGFloat = 420

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SheetMetrics.horizontal)
            .padding(.top, SheetMetrics.top)
            .padding(.bottom, SheetMetrics.bottom)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .glassSheetBackground()
    }
}

public extension View {
    func fittedSheet() -> some View {
        modifier(FittedSheetModifier())
    }
}

public struct GlassCircleButton<Content: View>: View {
    private let title: String
    private let size: CGFloat
    private let glassTint: Color?
    private let action: () -> Void
    private let content: Content

    public init(_ title: String, size: CGFloat = KinetLayout.barHeight, glassTint: Color? = nil, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.size = size
        self.glassTint = glassTint
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            content
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect((glassTint.map { Glass.regular.tint($0) } ?? .regular).interactive(), in: .circle)
        .accessibilityLabel(title)
    }
}

public struct GlassSymbolButton: View {
    private let title: String
    private let symbol: String
    private let tint: Color
    private let size: CGFloat
    private let fontSize: CGFloat
    private let weight: Font.Weight
    private let glassTint: Color?
    private let action: () -> Void

    public init(_ title: String, symbol: String, tint: Color = Palette.ink, size: CGFloat = KinetLayout.barHeight, fontSize: CGFloat = 19, weight: Font.Weight = .semibold, glassTint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.size = size
        self.fontSize = fontSize
        self.weight = weight
        self.glassTint = glassTint
        self.action = action
    }

    public var body: some View {
        GlassCircleButton(title, size: size, glassTint: glassTint, action: action) {
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(tint)
        }
    }
}

struct ThemedSheetBackground: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = ThemeColors.resolve(theme.themeID, dark: scheme == .dark)
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular.tint(colors.mid.opacity(scheme == .dark ? 0.55 : 0.4)), in: .rect)
    }
}
