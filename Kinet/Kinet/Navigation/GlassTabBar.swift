import KinetDesign
import SwiftUI
import UIKit

struct GlassTabBar: View, Equatable {
    let selected: AppPage
    let isWide: Bool
    let select: (AppPage) -> Void

    nonisolated static func == (lhs: GlassTabBar, rhs: GlassTabBar) -> Bool {
        lhs.selected == rhs.selected && lhs.isWide == rhs.isWide
    }

    var body: some View {
        TabView(selection: Binding(get: { selected }, set: { select($0) })) {
            ForEach(AppPage.allCases) { item in
                Tab(isWide ? "\u{2007}\u{2007}\(item.title)\u{2007}\u{2007}" : item.title, systemImage: item.symbol, value: item) {
                    Color.clear
                        .background(TransparentTabContainer())
                        .accessibilityHidden(true)
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        .frame(height: KinetLayout.barHeight + 4)
    }
}

private struct TransparentTabContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ClearingView {
        ClearingView()
    }

    func updateUIView(_ view: ClearingView, context: Context) {
        view.scheduleClear()
    }
}

private final class ClearingView: UIView {
    private var isScheduled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleClear()
    }

    func scheduleClear() {
        guard !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScheduled = false
            var current: UIView? = self
            while let candidate = current, !(candidate is UIWindow) {
                if candidate.backgroundColor != .clear { candidate.backgroundColor = .clear }
                if candidate.next is UITabBarController { break }
                current = candidate.superview
            }
        }
    }
}
