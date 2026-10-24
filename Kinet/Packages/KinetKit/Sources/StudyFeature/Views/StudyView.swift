import KinetCurrency
import KinetDesign
import SwiftUI
import UIKit

public struct StudyView: View {
    @Environment(\.appTheme) private var theme
    @Environment(StudyModel.self) private var study
    @Environment(Wallet.self) private var wallet
    @Environment(\.pageBottomInset) private var bottomInset
    private let isVisible: Bool
    @State private var confirmingEnd = false

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    public var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Studium", subtitle: subtitle, trailing: { EmptyView() })
                .guideTarget("studyHeader")
                .padding(.horizontal, KinetLayout.pageMargin)
                .padding(.top, 8)
            ZStack {
                StudyStage()
                    .guideTarget("stage")
                caption
                    .guideTarget("caption")
                    .frame(height: 56, alignment: .top)
                    .offset(y: ringSize / 2 + 30 + 28)
            }
            .offset(y: -26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(height: bottomInset - KinetLayout.pageMargin)
        }
        .animation(.smooth(duration: 0.5), value: study.state)
        .onChange(of: study.isRunning && isVisible, initial: true) { _, keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onChange(of: study.state) { _, _ in confirmingEnd = false }
    }

    private var subtitle: String {
        let cap = wallet.config.sources.first { $0.id == study.config.source }?.dailyCap ?? study.config.minuteRange.upperBound
        return "Dnes \(min(study.todayStudied, cap)) / \(MinuteFormatter.short(cap))"
    }

    @ViewBuilder
    private var caption: some View {
        switch study.state {
        case .idle:
            hint("Nastav čas a klepni doprostřed")
        case .running(let phase) where phase.kind == .cooldown:
            breathPrompt(start: phase.start, canResume: study.plan?.isPomodoro == true)
        case .running:
            endControl
        case .finished:
            hint("Minuty jsou připsané")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .multilineTextAlignment(.center)
            .transition(.opacity)
    }

    private func breathPrompt(start: Date, canResume: Bool) -> some View {
        TimelineView(BreathSchedule(start: start, breath: study.breath)) { timeline in
            let inhaling = study.breath.isInhaling(at: timeline.date, since: start)
            VStack(spacing: 6) {
                Text(inhaling ? "Nadechni se" : "Vydechni")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.8), value: inhaling)
                Text(canResume ? "Klepnutím ukončíš dýchání" : "Klepnutím skončíš")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .transition(.opacity)
    }

    private var endControl: some View {
        VStack(spacing: 14) {
            if confirmingEnd {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Připíše se \(MinuteFormatter.words(study.creditedIfEndedNow()))")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSecondary)
                }
                .transition(.opacity)
                HStack(spacing: 10) {
                    Button { confirmingEnd = false } label: {
                        Text("Zpět").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { try? study.finish(early: true) } label: {
                        Text("Ukončit").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(theme.accent)
                }
                .controlSize(.large)
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    Button { togglePause() } label: {
                        Image(systemName: study.isPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(study.isPaused ? "Pokračovat" : "Pozastavit")
                    Button { confirmingEnd = true } label: {
                        Image(systemName: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Ukončit")
                }
                .buttonStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.ink)
                .overlay { Rectangle().fill(Palette.hairline).frame(width: 1, height: 22) }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, confirmingEnd ? 22 : 0)
        .padding(.vertical, confirmingEnd ? 18 : 0)
        .frame(width: confirmingEnd ? 300 : 148)
        .glassEffect(.regular.interactive(!confirmingEnd), in: .rect(cornerRadius: 30))
        .animation(.spring(duration: 0.55, bounce: 0.15), value: confirmingEnd)
    }

    private func togglePause() {
        if study.isPaused { try? study.resume() } else { try? study.pause() }
    }
}
