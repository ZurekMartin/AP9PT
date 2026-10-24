import Charts
import KinetCurrency
import KinetDesign
import SwiftUI

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct Week: Identifiable {
    let index: Int
    let start: Date
    let days: [DayKey]
    var id: Int { index }
}

@MainActor
private struct WeeklyHistory {
    let weeks: [Week]
    let stats: [DayKey: DayStat]
    let yMax: Double

    init(wallet: Wallet) {
        let stats = Dictionary(wallet.recent.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        self.stats = stats
        weeks = Self.makeWeeks(wallet: wallet)
        yMax = Self.yDomain(stats: stats, shown: Set(wallet.config.displaySegments))
    }

    private static func makeWeeks(wallet: Wallet) -> [Week] {
        let calendar = wallet.calendar
        func start(of day: DayKey) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: day.startDate(in: calendar))?.start ?? day.startDate(in: calendar)
        }
        let last = start(of: wallet.today)
        let earliest = start(of: wallet.recent.first?.day ?? wallet.today)
        let first = max(earliest, calendar.date(byAdding: .day, value: -21, to: last) ?? earliest)
        var weeks: [Week] = []
        var cursor = first
        while cursor <= last {
            let days = (0..<7).map { offset -> DayKey in
                DayKey(date: calendar.date(byAdding: .day, value: offset, to: cursor) ?? cursor, calendar: calendar)
            }
            weeks.append(Week(index: weeks.count, start: cursor, days: days))
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? last.addingTimeInterval(86_400 * 8)
        }
        return weeks
    }

    private static func yDomain(stats: [DayKey: DayStat], shown: Set<String>) -> Double {
        let top = stats.values.map { stat in
            stat.incomeBySegment.filter { shown.contains($0.key) }.values.reduce(0, +)
        }.max() ?? 0
        if top > 100 { return Double((top + 99) / 100 * 100) }
        let step = top > 80 ? 20 : 10
        return Double(max(step * 2, Int((Double(top) * 1.08 / Double(step)).rounded(.up)) * step))
    }
}

struct WeeklyChartView: View {
    @Environment(Wallet.self) private var wallet
    @State private var weekIndex: Int?
    @State private var selected: DayKey?

    var body: some View {
        let history = WeeklyHistory(wallet: wallet)
        let weeks = history.weeks
        let stats = history.stats
        let yMax = history.yMax
        let current = weekIndex ?? weeks.last?.index ?? 0
        let activeWeek = weeks.first { $0.index == current }
        ContentCard {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow("Historie")
                        Text(selected.map(dayTitle) ?? rangeText(activeWeek))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(weeks) { week in
                            WeekChart(week: week, stats: stats, yMax: yMax, selected: $selected)
                                .containerRelativeFrame(.horizontal)
                                .id(week.index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $weekIndex)
                .defaultScrollAnchor(.trailing)
                .scrollIndicators(.hidden)
                .frame(height: 204)
                if weeks.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(weeks) { week in
                            Capsule()
                                .fill(week.index == current ? Palette.ink.opacity(0.7) : Palette.mist.opacity(0.4))
                                .frame(width: week.index == current ? 16 : 6, height: 6)
                        }
                    }
                    .animation(.smooth, value: current)
                }
                breakdown(activeWeek: activeWeek, stats: stats)
            }
        }
        .guideTarget("history")
        .onChange(of: weekIndex) { _, _ in selected = nil }
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.impact(weight: .light), trigger: weekIndex) { old, new in old != nil && new != nil }
        .onAppear { if weekIndex == nil { weekIndex = weeks.last?.index } }
    }

    private func breakdown(activeWeek: Week?, stats: [DayKey: DayStat]) -> some View {
        let days: [DayKey] = selected.map { [$0] } ?? (activeWeek?.days.filter { $0 <= wallet.today } ?? [])
        var income: [String: Int] = [:]
        for day in days {
            guard let stat = stats[day] else { continue }
            for (segment, minutes) in stat.incomeBySegment { income[segment, default: 0] += minutes }
        }
        return VStack(spacing: 10) {
            SegmentLegend(totals: income, showsBackground: false)
                .padding(.horizontal, -14)
                .frame(height: 36)
            SheetHint("Klepnutím na den uvidíš minuty.")
        }
    }

    private func dayTitle(_ day: DayKey) -> String {
        day.startDate(in: wallet.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.czech)).capitalizedFirst
    }

    private func rangeText(_ week: Week?) -> String {
        guard let week, let end = wallet.calendar.date(byAdding: .day, value: 6, to: week.start) else { return "" }
        let first = week.start.formatted(.dateTime.day().month(.defaultDigits).locale(.czech))
        let last = end.formatted(.dateTime.day().month(.defaultDigits).locale(.czech))
        return "\(first) – \(last)"
    }
}

private struct WeekChart: View {
    @Environment(Wallet.self) private var wallet
    let week: Week
    let stats: [DayKey: DayStat]
    let yMax: Double
    @Binding var selected: DayKey?

    var body: some View {
        let segments = wallet.config.displaySegments
        let calendar = wallet.calendar
        let end = calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
        Chart {
            ForEach(week.days, id: \.self) { day in
                let date = day.startDate(in: calendar)
                let stat = stats[day]
                let dim = selected != nil && selected != day
                ForEach(segments.filter { (stat?.incomeBySegment[$0] ?? 0) > 0 }, id: \.self) { segment in
                    BarMark(
                        x: .value("Den", date, unit: .day),
                        y: .value("Minuty", stat?.incomeBySegment[segment] ?? 0),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(by: .value("Zdroj", wallet.config.segmentTitle(for: segment)))
                    .cornerRadius(5)
                    .opacity(dim ? 0.35 : 1)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: segments.map { wallet.config.segmentTitle(for: $0) },
            range: segments.map { Palette.color(token: wallet.config.segmentTint(for: $0)) }
        )
        .chartLegend(.hidden)
        .chartXScale(domain: week.start...end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .top)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(anchor: .leading)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geometry[frame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        pick(date)
                    }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
        .environment(\.locale, .czech)
        .animation(.smooth(duration: 0.3), value: selected)
    }

    private func pick(_ date: Date) {
        let calendar = wallet.calendar
        guard let day = week.days.first(where: { calendar.isDate($0.startDate(in: calendar), inSameDayAs: date) }), day <= wallet.today else { return }
        selected = selected == day ? nil : day
    }
}
