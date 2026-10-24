import ProfileFeature
import KinetDesign
import PetFeature
import StudyFeature
import SwiftUI

enum RootSheet: String, Identifiable {
    case streak, settings, feed, customize
    var id: String { rawValue }
}

struct RootPager: View {
    @Environment(AppComposition.self) private var app
    @State private var page: AppPage? = .profile
    @State private var tracker = PageTracker()
    @State private var sheet: RootSheet?
    @State private var guideIndex: Int?
    @Namespace private var namespace

    var body: some View {
        GeometryReader { proxy in
            content
                .environment(\.screenInsets, proxy.safeAreaInsets)
        }
        .environment(tracker)
    }

    private var theme: AppTheme {
        AppTheme.make(skinID: app.pet.activeSkinID, themeID: app.pet.activeThemeID)
    }

    private var content: some View {
        let theme = theme
        return ZStack {
            OceanBackdrop(calm: app.study.isRunning && page == .study ? 1 : 0)
            pager
            BottomBar(page: $page, sheet: $sheet, namespace: namespace)
        }
        .overlayPreferenceValue(GuideAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if guideIndex != nil {
                    GuideHost(index: $guideIndex, frames: anchors.mapValues { proxy[$0] }, onFinish: finishGuide) {
                        await app.requestPermissions()
                    }
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.4), value: guideIndex == nil)
        }
        .environment(\.guideScrollsProfile, guideIndex.map { GuideContent.steps[$0].scrollsProfile } ?? false)
        .environment(\.appTheme, theme)
        .tint(theme.water)
        .sheet(item: $sheet) { presented in
            sheetContent(presented, theme: theme)
        }
        .onChange(of: app.preferences.guideCompleted) { _, _ in scheduleGuide() }
        .onChange(of: sheet) { _, _ in scheduleGuide() }
        .onChange(of: guideIndex) { _, index in
            guard let index, let target = AppPage(rawValue: GuideContent.steps[index].page), page != target else { return }
            withAnimation(.smooth(duration: 0.6)) { page = target }
        }
        .task { scheduleGuide() }
    }

    private func guideCanStart() -> Bool {
        !app.preferences.guideCompleted && guideIndex == nil && sheet == nil
    }

    private func scheduleGuide() {
        guard guideCanStart() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if guideCanStart() { guideIndex = 0 }
        }
    }

    private func finishGuide() {
        app.preferences.guideCompleted = true
        guideIndex = nil
        withAnimation(.smooth(duration: 0.6)) { page = .profile }
    }

    private var pager: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    PageSlot(page: .study) {
                        StudyView(isVisible: page == .study)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(AppPage.study)
                    PageSlot(page: .profile) {
                        ProfileView()
                            .refreshable { await app.refreshAll(force: true) }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(AppPage.profile)
                    PageSlot(page: .pet) {
                        PetView()
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(AppPage.pet)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .onAppear { proxy.scrollTo(AppPage.profile, anchor: .leading) }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)
            .onScrollGeometryChange(for: Double.self) { geometry in
                Double(geometry.contentOffset.x / max(1, geometry.containerSize.width))
            } action: { _, newValue in
                tracker.update(newValue)
            }
            .environment(\.pageBottomInset, KinetLayout.barHeight + KinetLayout.pageMargin * 2)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    @ViewBuilder
    private func sheetContent(_ presented: RootSheet, theme: AppTheme) -> some View {
        switch presented {
        case .streak:
            StreakSheet()
                .fittedSheet()
                .navigationTransition(.zoom(sourceID: presented, in: namespace))
                .environment(\.appTheme, theme)
                .tint(theme.water)
        case .feed:
            FeedSheet()
                .navigationTransition(.zoom(sourceID: presented, in: namespace))
                .environment(\.appTheme, theme)
                .tint(theme.water)
        case .customize:
            CustomizeSheet()
                .navigationTransition(.zoom(sourceID: presented, in: namespace))
                .environment(\.appTheme, theme)
                .tint(theme.water)
        case .settings:
            SettingsSheet()
                .navigationTransition(.zoom(sourceID: presented, in: namespace))
                .environment(\.appTheme, theme)
                .tint(theme.water)
        }
    }
}

private struct PageSlot<Content: View>: View {
    @Environment(PageTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    let page: AppPage
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.pageActive, isActive)
    }

    private var isActive: Bool {
        guard scenePhase == .active else { return false }
        let position = tracker.position
        switch page {
        case .study: return position < 0.99
        case .profile: return position > 0.01 && position < 1.99
        case .pet: return position > 1.01
        }
    }
}

private struct GuideHost: View {
    @Environment(PageTracker.self) private var tracker
    @Binding var index: Int?
    let frames: [String: CGRect]
    let onFinish: () -> Void
    let prepare: () async -> Void

    var body: some View {
        let current = index ?? 0
        GuideOverlay(
            steps: GuideContent.steps,
            index: Binding(get: { index ?? 0 }, set: { index = $0 }),
            frames: frames,
            isSettled: abs(tracker.position - Double(GuideContent.steps[current].page)) < 0.02,
            onFinish: onFinish,
            welcome: { context in
                GuideWelcome(context: context, prepare: prepare)
            }
        )
    }
}

private struct BottomBar: View {
    @Environment(\.appTheme) private var theme
    @Environment(PageTracker.self) private var tracker
    @Binding var page: AppPage?
    @Binding var sheet: RootSheet?
    let namespace: Namespace.ID
    @State private var target: AppPage?
    @State private var shown: AppPage = .profile

    var body: some View {
        let position = tracker.position
        let isWide = shown == .study
        VStack {
            Spacer()
            ZStack {
                GlassTabBar(selected: shown, isWide: true, select: choose)
                    .equatable()
                    .padding(.horizontal, -22)
                    .offset(y: 20)
                    .padding(.horizontal, KinetLayout.pageMargin)
                    .opacity(isWide ? 1 : 0)
                    .allowsHitTesting(isWide)
                HStack(alignment: .center, spacing: 10) {
                    leadingSlot(position: position)
                        .zIndex(1)
                    GlassTabBar(selected: shown, isWide: false, select: choose)
                        .equatable()
                        .padding(.horizontal, -22)
                        .offset(y: 20)
                    trailingSlot(position: position)
                        .zIndex(1)
                }
                .padding(.horizontal, KinetLayout.pageMargin)
                .opacity(isWide ? 0 : 1)
                .allowsHitTesting(!isWide)
            }
            .padding(.bottom, KinetLayout.pageMargin)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { shown = settled(position) }
        .onChange(of: position) { _, value in
            if let target, abs(value - Double(target.rawValue)) < 0.02 { self.target = nil }
            update(settled(value))
        }
        .onChange(of: page) { _, value in
            if let target, value != target { self.target = nil }
        }
    }

    private func settled(_ position: Double) -> AppPage {
        if let target { return target }
        return AppPage(rawValue: Int(min(2, max(0, position)).rounded())) ?? .profile
    }

    private func update(_ next: AppPage) {
        guard next != shown else { return }
        withAnimation(.smooth(duration: 0.3)) { shown = next }
    }

    private func choose(_ next: AppPage) {
        guard page != next else {
            update(next)
            return
        }
        target = next
        update(next)
        withAnimation(.smooth(duration: 0.55)) { page = next }
    }

    private func leadingSlot(position: Double) -> some View {
        ZStack {
            StreakBarButton { sheet = .streak }
                .guideTarget("streak")
                .matchedTransitionSource(id: RootSheet.streak, in: namespace)
                .modifier(SlotVisibility(position: position, page: 1))
                .allowsHitTesting(page == .profile)
            GlassSymbolButton("Nakrmit medúzu", symbol: "carrot.fill", tint: theme.water) { sheet = .feed }
                .guideTarget("feed")
                .matchedTransitionSource(id: RootSheet.feed, in: namespace)
                .modifier(SlotVisibility(position: position, page: 2))
                .allowsHitTesting(page == .pet)
        }
        .frame(width: KinetLayout.barHeight, height: KinetLayout.barHeight)
    }

    private func trailingSlot(position: Double) -> some View {
        ZStack {
            GlassSymbolButton("Nastavení", symbol: "gearshape.fill") { sheet = .settings }
            .guideTarget("settings")
            .matchedTransitionSource(id: RootSheet.settings, in: namespace)
            .modifier(SlotVisibility(position: position, page: 1))
            .allowsHitTesting(page == .profile)
            GlassSymbolButton("Úpravy akvária", symbol: "paintbrush.pointed.fill") { sheet = .customize }
                .guideTarget("customize")
                .matchedTransitionSource(id: RootSheet.customize, in: namespace)
                .modifier(SlotVisibility(position: position, page: 2))
                .allowsHitTesting(page == .pet)
        }
        .frame(width: KinetLayout.barHeight, height: KinetLayout.barHeight)
    }
}

private struct SlotVisibility: ViewModifier {
    let position: Double
    let page: Double

    func body(content: Content) -> some View {
        let visibility = max(0, 1 - abs(position - page) * 2.2)
        content
            .opacity(visibility)
            .scaleEffect(0.7 + 0.3 * visibility)
    }
}
