import KinetCurrency
import KinetDesign
import SwiftUI

typealias Transaction = KinetCurrency.Transaction

public struct ProfileView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(ProfileModel.self) private var profile
    @Environment(\.pageBottomInset) private var bottomInset
    @Environment(\.guideScrollsProfile) private var guideScrolls
    @Environment(PageTracker.self) private var tracker: PageTracker?
    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    PageHeader(title: "Profil", subtitle: dateText, trailing: { EmptyView() })
                        .id("top")
                    DonutChartView()
                    TodayCard()
                        .id("today")
                    WeeklyChartView()
                }
                .padding(.horizontal, KinetLayout.pageMargin)
                .padding(.top, 8)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                tracker?.updateProfileTop(atTop)
            }
            .onChange(of: guideScrolls) { _, scrolled in
                withAnimation(.smooth(duration: 0.6)) {
                    if scrolled { proxy.scrollTo("today", anchor: UnitPoint(x: 0.5, y: 0.1)) } else { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var dateText: String {
        wallet.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech))
    }
}
