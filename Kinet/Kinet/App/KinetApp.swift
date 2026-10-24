import ProfileFeature
import KinetCurrency
import KinetDesign
import PetFeature
import StudyFeature
import SwiftUI

@main
struct KinetApp: App {
    @State private var composition: AppComposition?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let composition {
                    LoadedRoot(composition: composition)
                        .transition(.opacity)
                } else {
                    LandingView()
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.5), value: composition == nil)
            .task {
                guard composition == nil else { return }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(80))
                composition = AppComposition()
            }
        }
    }
}

private struct LoadedRoot: View {
    let composition: AppComposition
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
                RootPager()
                    .id(composition.preferences.isDemoMode)
                if composition.isBusy {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Připravuji ukázková data…")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: composition.isBusy)
            .environment(composition)
            .environment(composition.feedback)
            .environment(composition.wallet)
            .environment(composition.profile)
            .environment(composition.study)
            .environment(composition.pet)
            .environment(\.locale, .czech)
            .task(id: scenePhase) {
                guard scenePhase == .active else {
                    composition.wallet.save()
                    return
                }
                if composition.preferences.isDemoMode && !composition.preferences.demoSeeded { await composition.seedDemo() }
                await composition.refreshAll()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(120), tolerance: .seconds(10))
                    if Task.isCancelled { break }
                    await composition.refreshAll()
                }
            }
    }
}
