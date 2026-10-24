import KinetCurrency
import KinetDesign
import SwiftUI

public struct FeedSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(PetModel.self) private var model
    @Environment(Wallet.self) private var wallet
    @Environment(Feedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var portion = 0
    @State private var message: String?

    public init() {}

    private var range: ClosedRange<Int> { model.config.rationRange }
    private var missing: Int { max(0, portion - model.fedToday) }
    private var feedNow: Int { min(missing, model.maxFeedableNow) }

    public var body: some View {
        let daily = model.config.maxDailyFeed
        VStack(spacing: SheetMetrics.spacing) {
            SheetHeader(
                "Krmení",
                subtitle: "K dispozici \(MinuteFormatter.string(wallet.balance))",
                symbol: "carrot.fill",
                tint: theme.accent
            )
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Denní porce")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(MinuteFormatter.short(portion))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(portion)))
                        .foregroundStyle(theme.accent)
                }
                FeedTrack(fed: model.fedToday, portion: $portion, range: range, step: model.config.rationStep, daily: daily, tint: theme.accent) {
                    commit()
                }
                HStack(spacing: 16) {
                    legend("Nakrmeno \(MinuteFormatter.short(model.fedToday))", opacity: 1)
                    legend("Zbývá \(MinuteFormatter.short(missing))", opacity: 0.45)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 12) {
                Button {
                    feed()
                } label: {
                    Text(feedNow > 0 ? "Dokrmit teď \(MinuteFormatter.words(feedNow))" : (missing == 0 ? "Porce je splněná" : "Dokrmit teď"))
                        .contentTransition(.numericText(value: Double(feedNow)))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .disabled(feedNow == 0)
                SheetHint(message ?? hint, isAlert: message != nil)
            }
        }
        .animation(.smooth, value: message)
        .animation(.smooth(duration: 0.25), value: portion)
        .onAppear { portion = model.ration }
        .onDisappear { commit() }
        .onChange(of: portion) { oldValue, value in
            guard oldValue != 0 else { return }
            message = nil
            feedback.play(value % 30 == 0 ? .detent : .tick)
        }
        .fittedSheet()
    }

    private func legend(_ text: String, opacity: Double) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.accent.opacity(opacity))
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var hint: String {
        if model.fedToday >= model.config.maxDailyFeed {
            return "Medúza je dnes plně nasycená. Zítra zase."
        }
        if missing > 0, feedNow == 0 {
            return "Teď nemáš volné minuty. Zbytek porce medúza dostane večer, pokud nějaké získáš."
        }
        if missing > 0, feedNow < missing {
            return "Teď stačí minuty na \(MinuteFormatter.words(feedNow)). Zbytek porce medúza dostane večer."
        }
        return "Porci medúza dostane každý večer sama. Dokrmením ji dostane hned a víc ji to potěší."
    }

    private func commit() {
        guard portion > 0, portion != model.ration else { return }
        model.setRation(portion)
    }

    private func feed() {
        commit()
        do {
            try model.feed(minutes: feedNow)
            message = nil
            dismiss()
        } catch {
            switch error {
            case .insufficientFunds: message = "Zatím nemáš dost minut. Pár kroků pomůže."
            case .invalidAmount: message = "Medúza je dnes krásně nasycená."
            case .reserved: message = "Tyhle minuty jsou rezervované."
            }
        }
    }
}

private struct FeedTrack: View {
    let fed: Int
    @Binding var portion: Int
    let range: ClosedRange<Int>
    let step: Int
    let daily: Int
    let tint: Color
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 20
            let dot: CGFloat = 7
            let trackHeight: CGFloat = 10
            let usable = proxy.size.width - knob
            let total = Double(max(1, daily))
            let positionX: (Double) -> CGFloat = { knob / 2 + usable * CGFloat(min(total, max(0, $0)) / total) }
            let fedX = positionX(Double(fed))
            let portionX = positionX(Double(portion))
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(tint.opacity(0.16))
                    .frame(height: trackHeight)
                    .offset(y: (knob - trackHeight) / 2)
                Capsule()
                    .fill(tint.opacity(0.45))
                    .frame(width: max(trackHeight, portionX + trackHeight / 2), height: trackHeight)
                    .offset(y: (knob - trackHeight) / 2)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: fed > 0 ? min(proxy.size.width, fedX + trackHeight / 2) : 0, height: trackHeight)
                    .offset(y: (knob - trackHeight) / 2)
                ForEach(0...(daily / step), id: \.self) { index in
                    let minutes = index * step
                    Circle()
                        .fill(minutes <= max(portion, fed) ? tint : Palette.mist.opacity(0.35))
                        .frame(width: dot, height: dot)
                        .position(x: positionX(Double(minutes)), y: knob + 14)
                }
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .overlay { Circle().strokeBorder(tint, lineWidth: 2) }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .position(x: portionX, y: knob / 2)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard usable > 0 else { return }
                        let minutes = Double(drag.location.x - knob / 2) / Double(usable) * total
                        let stepped = Int((minutes / Double(step)).rounded()) * step
                        let next = min(range.upperBound, max(range.lowerBound, stepped))
                        if next != portion { portion = next }
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 20 + 22)
        .accessibilityElement()
        .accessibilityLabel("Denní porce")
        .accessibilityValue("\(portion) minut")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: portion = min(range.upperBound, portion + step)
            case .decrement: portion = max(range.lowerBound, portion - step)
            @unknown default: break
            }
            onCommit()
        }
    }
}

public struct CustomizeSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(PetModel.self) private var model
    @Environment(Wallet.self) private var wallet
    @Environment(Feedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var category: ShopCategory = .decor
    @State private var focusID: String?
    @State private var message: String?

    public init() {}

    private var items: [ShopItem] {
        model.config.catalog.filter { $0.category == category }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            scrollContent
                .onChange(of: focusID) { _, id in
                    guard let id else { return }
                    withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                }

        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: SheetMetrics.spacing) {
                SheetHeader(
                    "Úpravy",
                    subtitle: "K dispozici \(MinuteFormatter.words(wallet.spendable(for: nil))) · Úroveň \(model.vitals.level)",
                    symbol: "paintbrush.pointed.fill",
                    tint: theme.water
                )
                Picker("Kategorie", selection: $category.animation(.smooth)) {
                    ForEach(ShopCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        CustomizeCard(item: item, state: state(of: item), isFocused: focusID == item.id, scheme: scheme, action: { tap(item) }, confirm: { buy(item) }, cancel: { focusID = nil })
                            .id(item.id)
                    }
                }

                SheetHint(message ?? "Koupené kousky vybereš klepnutím, nové si můžeš pořídit za minuty.", isAlert: message != nil)
            }
            .padding(.horizontal, SheetMetrics.horizontal)
            .padding(.top, SheetMetrics.top)
            .padding(.bottom, SheetMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .animation(.spring(duration: 0.45, bounce: 0.15), value: focusID)
        .animation(.smooth, value: message)
        .onChange(of: category) { _, _ in focusID = nil; message = nil }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .glassSheetBackground()
    }

    private func state(of item: ShopItem) -> CustomizeCard.State {
        if item.requiredLevel > model.vitals.level { return .locked(item.requiredLevel) }
        guard item.category != .experience, model.ownedIDs.contains(item.id) else { return .available }
        switch item.category {
        case .theme: return .owned(isActive: model.activeThemeID == item.id)
        case .skin: return .owned(isActive: model.activeSkinID == item.id)
        default: return .owned(isActive: !model.hiddenDecorIDs.contains(item.id))
        }
    }

    private func tap(_ item: ShopItem) {
        message = nil
        if case .owned = state(of: item) {
            focusID = nil
            switch item.category {
            case .theme: model.setTheme(item.id)
            case .skin: model.setSkin(item.id)
            default: model.setDecor(item.id, hidden: !model.hiddenDecorIDs.contains(item.id))
            }
            feedback.play(.softTap)
        } else if item.requiredLevel > model.vitals.level {
            focusID = nil
            message = "Tohle se odemkne na úrovni \(item.requiredLevel)."
        } else {
            focusID = focusID == item.id ? nil : item.id
        }
    }

    private func buy(_ item: ShopItem) {
        do {
            try model.purchase(item.id)
            message = nil
            focusID = nil
            if item.category == .experience { dismiss() }
        } catch {
            switch error {
            case .levelTooLow(let level): message = "Tohle se odemkne na úrovni \(level)."
            case .alreadyOwned: message = "To už v akváriu máš."
            case .dailyExperienceLimit: message = "Dnešní zážitek už proběhl. Zítra zase."
            case .spend(.reserved(let minutes, _)): message = "Medúza má dnes ještě hlad, nech jí aspoň \(MinuteFormatter.words(minutes))."
            case .spend(.insufficientFunds(let missing)): message = "Chybí ti ještě \(MinuteFormatter.words(missing))."
            case .spend(.invalidAmount): message = "Něco se nepovedlo."
            }
        }
    }
}

struct CustomizeCard: View {
    @Environment(\.appTheme) private var theme
    enum State: Equatable {
        case available, owned(isActive: Bool), locked(Int)
    }

    let item: ShopItem
    let state: State
    let isFocused: Bool
    let scheme: ColorScheme
    let action: () -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        if isFocused, state == .available {
            confirmTile
        } else {
            tile
        }
    }

    private var confirmTile: some View {
        VStack(spacing: 14) {
            Text(MinuteFormatter.short(item.price))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.water)
            HStack(spacing: 14) {
                GlassSymbolButton("Zrušit", symbol: "xmark", size: 46, fontSize: 16, weight: .bold, action: cancel)
                GlassSymbolButton("Koupit \(item.title)", symbol: "checkmark", tint: theme.water, size: 46, fontSize: 16, weight: .bold, glassTint: theme.water.opacity(0.25), action: confirm)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Palette.surface, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.water, lineWidth: 2)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var tile: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(height: 58)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                footer
            }
            .padding(12)
            .background(Palette.surface, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(outline, lineWidth: isHighlighted || isFocused ? 2 : 1)
            }
            .opacity(state == .available || isFocused ? 1 : (isOwned ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var isOwned: Bool {
        if case .owned = state { return true }
        return false
    }

    private var isHighlighted: Bool {
        if case .owned(true) = state, item.category != .decor { return true }
        return false
    }

    private var outline: Color {
        if isFocused { return theme.accent }
        return isHighlighted ? theme.water : Palette.hairline
    }

    private static func themeID(forSkin id: String) -> String {
        switch id {
        case "sageSkin": "coralReef"
        case "sandSkin": "polarDeep"
        case "opalSkin": "bioluminescence"
        default: "lagoon"
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.category {
        case .theme:
            let colors = ThemeColors.resolve(item.id, dark: scheme == .dark)
            LinearGradient(colors: [colors.top, colors.mid, colors.bottom], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottom) { colors.floor.frame(height: 10) }
        case .skin:
            let pair = JellyfishRenderer.colors(skinID: item.id, time: 0, mood: .happy)
            let matching = ThemeColors.resolve(Self.themeID(forSkin: item.id), dark: scheme == .dark)
            LinearGradient(colors: [matching.top, matching.mid, matching.bottom], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottom) { matching.floor.frame(height: 10) }
                .overlay {
                    Circle()
                        .fill(LinearGradient(colors: [pair.primary, pair.secondary], startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                        .offset(y: -4)
                }
        default:
            ZStack {
                tint.opacity(0.14)
                Image(systemName: item.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch state {
        case .available:
            Text(MinuteFormatter.short(item.price))
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.accent)
        case .owned(let isActive):
            Label(ownedTitle(isActive), systemImage: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(isActive ? Palette.sage : Palette.inkSecondary)
        case .locked(let level):
            Label("Úroveň \(level)", systemImage: "lock.fill")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func ownedTitle(_ isActive: Bool) -> String {
        if item.category == .decor { return isActive ? "Zobrazeno" : "Skryto" }
        return isActive ? "Vybráno" : "Vybrat"
    }

    private var tint: Color {
        switch item.category {
        case .decor: Palette.sage
        case .theme: theme.water
        case .skin: Palette.coral
        case .experience: Palette.sand
        }
    }
}
