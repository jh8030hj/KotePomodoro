import SwiftUI
import SwiftData
import Charts

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "이번 주"
    case month = "이번 달"
    case all = "전체"

    var id: Self { self }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: true
        case .week: calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        case .month: calendar.isDate(date, equalTo: .now, toGranularity: .month)
        }
    }
}

struct StatsView: View {
    @Query private var sessions: [WorkSession]
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]
    @Query private var todos: [TodoItem]
    @State private var period: StatsPeriod = .week
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    private var periodSessions: [WorkSession] { sessions.filter { period.contains($0.date) } }
    private var totalTime: TimeInterval { periodSessions.map(\.duration).reduce(0, +) }

    private var todayTime: TimeInterval {
        sessions.filter { calendar.isDateInToday($0.date) }.map(\.duration).reduce(0, +)
    }

    private var doneTodos: Int {
        todos.filter { $0.isDone && $0.doneAt.map { period.contains($0) } == true }.count
    }

    /// 하루 30분 이상 집중한 날이 오늘(또는 어제)부터 며칠 연속인지
    private var streak: Int {
        let byDay = Dictionary(grouping: sessions, by: { calendar.startOfDay(for: $0.date) })
            .mapValues { $0.map(\.duration).reduce(0, +) }
        let days = Set(byDay.filter { $0.value >= 30 * 60 }.keys)
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// 기간 안에서 카테고리별 시간 (많은 순)
    private var categoryTimes: [(category: TaskCategory, time: TimeInterval)] {
        let times = Dictionary(grouping: periodSessions, by: \.categoryKey).mapValues { $0.map(\.duration).reduce(0, +) }
        return categories.compactMap { category in
            guard let time = times[category.key], time > 0 else { return nil }
            return (category, time)
        }
        .sorted { $0.time > $1.time }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    recordStats
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationDestination(for: String.self) { key in
                if let category = categories.category(key) {
                    CategoryStatsView(category: category)
                }
            }
        }
    }

    @ViewBuilder
    private var recordStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("오늘 \(durationString(todayTime)) 집중했어요")
                .font(.title3.bold())
            Picker("기간", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            StatCard(title: "집중 시간", value: durationString(totalTime))
            StatCard(title: "연속 (하루 30분+)", value: "\(streak)일")
            StatCard(title: "끝낸 할 일", value: "\(doneTodos)개")
        }

        categorySection
        dailySection

        VStack(alignment: .leading, spacing: 8) {
            Text("잔디 (최근 26주, 하루 집중 시간)").font(.headline)
            HeatmapView(sessions: sessions)
        }
    }

    // MARK: - 카테고리별 시간

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("카테고리별 시간 (\(period.rawValue))").font(.headline)
            if categoryTimes.isEmpty {
                emptyText
            } else {
                let maxTime = categoryTimes.first?.time ?? 1
                ForEach(categoryTimes, id: \.category.key) { item in
                    NavigationLink(value: item.category.key) {
                        HStack(spacing: 8) {
                            CategoryBadge(category: item.category, font: .callout)
                                .frame(width: 130, alignment: .leading)
                            GeometryReader { proxy in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.category.color)
                                    .frame(width: max(proxy.size.width * item.time / maxTime, 4))
                            }
                            .frame(height: 10)
                            Text(durationString(item.time))
                                .font(.callout)
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                            Text("\(Int((item.time / max(totalTime, 1) * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(item.category.name) 자세히 보기")
                }
            }
        }
    }

    // MARK: - 날짜별 막대

    private struct DayBar: Identifiable {
        let id = UUID()
        let day: Date
        let category: String
        let minutes: Double
    }

    /// 이번 주: 요일별 / 이번 달: 날짜별 / 전체: 최근 12주 주별
    private var dayBars: [DayBar] {
        let unit: Calendar.Component = period == .all ? .weekOfYear : .day
        let source: [WorkSession]
        if period == .all {
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            let start = calendar.date(byAdding: .weekOfYear, value: -11, to: thisWeek) ?? thisWeek
            source = sessions.filter { $0.date >= start }
        } else {
            source = periodSessions
        }
        let grouped = Dictionary(grouping: source) { session in
            calendar.dateInterval(of: unit, for: session.date)?.start ?? session.date
        }
        return grouped.flatMap { day, items in
            Dictionary(grouping: items, by: \.categoryKey).map { key, list in
                DayBar(day: day, category: categories.category(key)?.name ?? "기타",
                       minutes: list.map(\.duration).reduce(0, +) / 60)
            }
        }
    }

    private var dailySection: some View {
        let bars = dayBars
        // 막대에 나온 카테고리 순서대로 색을 붙인다 (지운 카테고리는 회색 '기타')
        let names = categories.map(\.name).filter { name in bars.contains { $0.category == name } }
            + (bars.contains { bar in !categories.contains { $0.name == bar.category } } ? ["기타"] : [])
        let colors = names.map { name in categories.first { $0.name == name }?.color ?? .gray }
        let unit: Calendar.Component = period == .all ? .weekOfYear : .day
        let domain: ClosedRange<Date> = {
            switch period {
            case .week:
                let week = calendar.dateInterval(of: .weekOfYear, for: .now)!
                return week.start...calendar.date(byAdding: .day, value: 6, to: week.start)!
            case .month:
                let month = calendar.dateInterval(of: .month, for: .now)!
                return month.start...calendar.date(byAdding: .day, value: -1, to: month.end)!
            case .all:
                let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
                return calendar.date(byAdding: .weekOfYear, value: -11, to: thisWeek)!...thisWeek
            }
        }()
        let selectedTotal = selectedDay.map { day in
            bars.filter { calendar.isDate($0.day, equalTo: day, toGranularity: unit) }.map(\.minutes).reduce(0, +)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(period == .all ? "주별 집중 시간 (최근 12주)" : "날짜별 집중 시간").font(.headline)
                Spacer()
                if let selectedDay, let selectedTotal {
                    Text(selectedDay.formatted(.dateTime.month().day()) + (period == .all ? " 주" : "") + " · "
                         + durationString(selectedTotal * 60))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if bars.isEmpty {
                emptyText
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("날짜", bar.day, unit: unit),
                        y: .value("분", bar.minutes)
                    )
                    .foregroundStyle(by: .value("카테고리", bar.category))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartXScale(domain: domain.lowerBound...calendar.date(byAdding: unit, value: 1, to: domain.upperBound)!)
                .chartXAxis {
                    if period == .week {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) { Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m") }
                        }
                    }
                }
                .chartXSelection(value: $selectedDay)
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 170)
            }
        }
    }

    private var emptyText: some View {
        Text("이 기간에는 기록이 없어요.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)  // "12시간 30분"처럼 길어도 한 줄에 맞춤
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 잔디. 하루에 집중한 시간이 길수록 진하다.
struct HeatmapView: View {
    let sessions: [WorkSession]
    var weeks = 26
    var tint: Color = .green

    private let calendar = Calendar.current

    var body: some View {
        let minutes = Dictionary(grouping: sessions, by: { calendar.startOfDay(for: $0.date) })
            .mapValues { $0.map(\.duration).reduce(0, +) / 60 }
        let today = calendar.startOfDay(for: .now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek

        VStack(alignment: .leading, spacing: 6) {
            // 칸 크기를 창 너비에 맞춰 가로를 꽉 채운다
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                            let value = minutes[day] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day > today ? 0 : level(value)))
                                .aspectRatio(1, contentMode: .fit)
                                .help("\(day.formatted(.dateTime.month().day())): \(durationString(value * 60))")
                        }
                    }
                }
            }
            HStack(spacing: 3) {
                Text("0").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: n)).frame(width: 10, height: 10)
                }
                Text("4시간+").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// 0분 / ~1시간 / ~2시간 / ~4시간 / 4시간 이상
    private func level(_ minutes: Double) -> Int {
        switch minutes {
        case ..<1: 0
        case ..<60: 1
        case ..<120: 2
        case ..<240: 3
        default: 4
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.15)
        case 1: tint.opacity(0.35)
        case 2: tint.opacity(0.55)
        case 3: tint.opacity(0.75)
        default: tint
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .frame(width: 440, height: 600)
}
