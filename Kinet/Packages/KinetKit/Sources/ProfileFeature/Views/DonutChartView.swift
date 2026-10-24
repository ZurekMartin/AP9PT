import Charts
import KinetCurrency
import KinetDesign
import SwiftUI

struct DonutChartView: View {
    @Environment(\.appTheme) private var theme
    @Environment(Wallet.self) private var wallet
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 40

    private var totals: [String: Int] {
        Dictionary(grouping: wallet.donut, by: \.segment).mapValues { $0.reduce(0) { $0 + $1.minutes } }
    }

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                if wallet.donut.isEmpty {
                    Circle()
                        .stroke(Palette.mist.opacity(0.3), lineWidth: 24)
                        .padding(12)
                } else {
                    Chart(wallet.donut.filter { $0.minutes > 0 }) { slice in
                        SectorMark(angle: .value("Minuty", slice.minutes), innerRadius: .ratio(0.74), angularInset: 1.5)
                            .cornerRadius(5)
                            .foregroundStyle(Palette.color(token: slice.tint).opacity(slice.isSpent ? 0.22 : 1))
                    }
                    .chartLegend(.hidden)
                    .animation(.smooth(duration: 0.8), value: wallet.donut)
                }
                TideFill(level: Double(wallet.balance) / Double(max(1, wallet.config.carryoverCap)), tint: theme.water)
                    .padding(46)
                VStack(spacing: 2) {
                    Text(MinuteFormatter.string(wallet.balance))
                        .font(.system(size: balanceSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("k dispozici")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, 60)
                .animation(.smooth, value: wallet.balance)
            }
            .frame(width: 270, height: 270)
            .guideTarget("donut")
            SegmentLegend(totals: totals)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zůstatek \(MinuteFormatter.string(wallet.balance))")
    }
}
