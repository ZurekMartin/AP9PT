import KinetCurrency
import KinetDesign
import SwiftUI

struct SegmentLegend: View {
    @Environment(Wallet.self) private var wallet
    let totals: [String: Int]
    var showsBackground = true

    private var visible: [String] { wallet.config.displaySegments.filter { (totals[$0] ?? 0) > 0 } }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(visible, id: \.self) { item($0) }
        }
        .padding(.horizontal, showsBackground ? 12 : 0)
        .padding(.vertical, showsBackground ? 7 : 0)
        .background { if showsBackground { Capsule().fill(Palette.surface) } }
        .fixedSize()
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.4), value: totals)
    }

    private func item(_ segment: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(Palette.color(token: wallet.config.segmentTint(for: segment))).frame(width: 5, height: 5)
            Text("\(wallet.config.segmentTitle(for: segment)) \(MinuteFormatter.compact(totals[segment] ?? 0))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.inkSecondary)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .fixedSize()
    }
}
