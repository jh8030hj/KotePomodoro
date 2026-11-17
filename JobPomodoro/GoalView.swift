import SwiftUI
import SwiftData
import Charts

/// 목표 탭: 카테고리별 이번 주 목표·오늘 목표를 정하고 진행을 본다
struct GoalView: View {
    @Query private var sessions: [WorkSession]
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]

    private let calendar = Calendar.current

    private var weekSessions: [WorkSession] {
        sessions.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    private var weekDone: [String: TimeInterval] {
        Dictionary(grouping: weekSessions, by: \.categoryKey).mapValues { $0.map(\.duration).reduce(0, +) }
    }

    private var todayDone: [String: TimeInterval] {
        Dictionary(grouping: weekSessions.filter { calendar.isDateInToday($0.date) }, by: \.categoryKey)
            .mapValues { $0.map(\.duration).reduce(0, +) }
    }

    /// 이번 주에 오늘 포함 남은 날 수
    private var daysLeft: Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 1 }
        return max(calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: week.end).day ?? 1, 1)
    }

    var body: some View {
        let active = categories.active
        let weekDone = weekDone
        let todayDone = todayDone
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary(active, weekDone: weekDone, todayDone: todayDone)

                Text("카테고리별 목표").font(.headline)
                Text("이번 주 목표와 오늘 목표를 정하세요. 오늘 목표는 오늘만 쓰이고, 내일은 새로 정해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, -12)

                ForEach(active) { category in
                    GoalCard(
                        category: category,
                        weekDone: weekDone[category.key] ?? 0,
                        todayDone: todayDone[category.key] ?? 0,
                        daysLeft: daysLeft
                    )
                }

                weekChart(active)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    // MARK: - 맨 위 요약

    private func summary(_ active: [TaskCategory], weekDone: [String: TimeInterval], todayDone: [String: TimeInterval]) -> some View {
        let weekly = active.filter { $0.weeklyGoalMinutes > 0 }
        let weekGoal = weekly.map { TimeInterval($0.weeklyGoalMinutes * 60) }.reduce(0, +)
        // 한 카테고리가 넘쳐도 다른 카테고리 부족분을 채우지 않게 목표까지만 센다
        let weekCounted = weekly.map { min(weekDone[$0.key] ?? 0, TimeInterval($0.weeklyGoalMinutes * 60)) }.reduce(0, +)
        let weekRemaining = max(weekGoal - weekCounted, 0)
        let ratio = weekGoal > 0 ? weekCounted / weekGoal : 0

        let daily = active.filter { $0.todayGoalMinutes > 0 }
        let todayGoal = daily.map { TimeInterval($0.todayGoalMinutes * 60) }.reduce(0, +)
        let todayCounted = daily.map { min(todayDone[$0.key] ?? 0, TimeInterval($0.todayGoalMinutes * 60)) }.reduce(0, +)

        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(weekGoal > 0 ? "\(Int((ratio * 100).rounded()))%" : "-")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("이번 주").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 5) {
                if weekGoal > 0 {
                    Text("이번 주 \(durationString(weekCounted)) / \(durationString(weekGoal))")
                        .font(.headline)
                        .monospacedDigit()
                    Text(weekRemaining > 0
                         ? "남은 목표 \(durationString(weekRemaining)) · 남은 \(daysLeft)일"
                         : "이번 주 목표를 모두 채웠어요!")
                        .font(.callout)
                        .foregroundStyle(weekRemaining > 0 ? Color.secondary : Color.green)
                } else {
                    Text("이번 주 목표가 없어요").font(.headline)
                }
                Divider().padding(.vertical, 2)
                if todayGoal > 0 {
                    Text("오늘 \(durationString(todayCounted)) / \(durationString(todayGoal))")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(value: min(todayCounted / todayGoal, 1))
                } else {
                    Text("오늘 목표를 아래에서 정해 보세요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 요일별

    private struct DayTotal: Identifiable {
        let day: Date
        let minutes: Double
        var id: Date { day }
    }

    @ViewBuilder
    private func weekChart(_ active: [TaskCategory]) -> some View {
        let weekly = active.filter { $0.weeklyGoalMinutes > 0 }
        if !weekly.isEmpty, let week = calendar.dateInterval(of: .weekOfYear, for: .now) {
            let keys = Set(weekly.map(\.key))
            let byDay = Dictionary(grouping: weekSessions.filter { keys.contains($0.categoryKey) }) {
                calendar.startOfDay(for: $0.date)
            }
            let days = (0..<7).compactMap { offset -> DayTotal? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
                return DayTotal(day: day, minutes: (byDay[day] ?? []).map(\.duration).reduce(0, +) / 60)
            }
            let pace = Double(weekly.map(\.weeklyGoalMinutes).reduce(0, +)) / 7

            VStack(alignment: .leading, spacing: 8) {
                Text("이번 주 요일별").font(.headline)
                Chart {
                    ForEach(days) { item in
                        BarMark(
                            x: .value("요일", item.day, unit: .day),
                            y: .value("분", item.minutes)
                        )
                        .foregroundStyle(item.minutes >= pace ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .cornerRadius(3)
                    }
                    RuleMark(y: .value("하루 평균 목표", pace))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("하루 평균 목표 " + durationString(pace * 60))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
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
                .frame(height: 140)
                Text("목표가 있는 카테고리 합계예요. 진한 막대는 하루 평균 목표(주간 목표 ÷ 7)를 넘긴 날이에요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 카테고리 하나의 목표 카드
private struct GoalCard: View {
    @Bindable var category: TaskCategory
    let weekDone: TimeInterval
    let todayDone: TimeInterval
    let daysLeft: Int

    private var weekGoal: TimeInterval { TimeInterval(category.weeklyGoalMinutes * 60) }
    private var todayGoal: TimeInterval { TimeInterval(category.todayGoalMinutes * 60) }
    private var weekRemaining: TimeInterval { max(weekGoal - weekDone, 0) }

    /// 오늘 몫 추천: 이번 주 남은 목표 ÷ 남은 날 (오늘 이미 한 시간 포함), 30분 단위로 올림
    private var suggestedToday: Int {
        let perDay = (weekRemaining + todayDone) / Double(daysLeft) / 60
        return Int((perDay / 30).rounded(.up)) * 30
    }

    /// 오늘 목표를 채웠을 때 이번 주에 남는 시간
    private var weekRemainingAfterToday: TimeInterval {
        max(weekRemaining - max(todayGoal - todayDone, 0), 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryBadge(category: category, font: .headline)
                Spacer()
                if weekGoal > 0 {
                    Text("이번 주 \(durationString(weekDone)) / \(durationString(weekGoal))")
                        .font(.callout)
                        .monospacedDigit()
                }
            }

            if weekGoal > 0 {
                ProgressView(value: min(weekDone / weekGoal, 1))
                    .tint(category.color)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("이번 주 목표").foregroundStyle(.secondary)
                    HoursField(title: "\(category.name) 이번 주 목표", minutes: $category.weeklyGoalMinutes)
                    Text(weekGoal == 0 ? "" : weekRemaining > 0 ? "남은 \(durationString(weekRemaining))" : "달성 ✓")
                        .foregroundStyle(weekRemaining > 0 ? Color.secondary : Color.green)
                }
                GridRow {
                    Text("오늘 목표").foregroundStyle(.secondary)
                    HoursField(title: "\(category.name) 오늘 목표", minutes: $category.todayGoalMinutes, maxHours: 16)
                    if weekRemaining > 0 && suggestedToday > 0 && suggestedToday != category.todayGoalMinutes {
                        Button("추천 \(durationString(TimeInterval(suggestedToday * 60)))") {
                            category.todayGoalMinutes = suggestedToday
                        }
                        .controlSize(.small)
                        .help("이번 주 남은 목표를 남은 \(daysLeft)일로 나눈 값")
                    } else {
                        Text("")
                    }
                }
            }
            .font(.callout)

            if todayGoal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("오늘 \(durationString(todayDone)) / \(durationString(todayGoal))")
                            .monospacedDigit()
                        Spacer()
                        if todayDone >= todayGoal {
                            Label("오늘 목표 달성", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    ProgressView(value: min(todayDone / todayGoal, 1))
                        .tint(category.color)
                    if weekGoal > 0 {
                        Text(weekRemainingAfterToday > 0
                             ? "오늘 목표를 채우면 이번 주 남은 목표: \(durationString(weekRemainingAfterToday))"
                             : "오늘 목표를 채우면 이번 주 목표 달성!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(weekRemainingAfterToday > 0 ? Color.primary : Color.green)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .opacity(weekGoal == 0 && todayGoal == 0 ? 0.75 : 1)
    }
}

#Preview {
    GoalView()
        .modelContainer(for: AppSchema.models, inMemory: true)
        .frame(width: 440, height: 640)
}
