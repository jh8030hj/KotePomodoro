import SwiftUI
import SwiftData
import Charts

/// 카테고리 하나의 자세한 통계. 양식에 있는 칸(결과·별점·개수·회사…)만 보여준다.
struct CategoryStatsView: View {
    let category: TaskCategory

    @Query private var allSessions: [WorkSession]
    @State private var period: StatsPeriod = .week

    private var form: CategoryForm { category.form }
    private var sessions: [WorkSession] { allSessions.filter { $0.categoryKey == category.key } }
    private var periodSessions: [WorkSession] { sessions.filter { period.contains($0.date) } }

    private var totalTime: TimeInterval { periodSessions.map(\.duration).reduce(0, +) }

    private var cards: [(String, String)] {
        let list = periodSessions
        var result: [(String, String)] = [
            ("집중 시간", durationString(totalTime)),
            ("기록", "\(list.count)번"),
        ]
        if form.outcomes == ["성공", "실패"] {
            let success = list.filter { $0.outcome == "성공" }.count
            result.append(("성공률", list.isEmpty ? "-" : "\(Int((Double(success) / Double(list.count) * 100).rounded()))%"))
        }
        if let title = form.ratingTitle {
            let rated = list.filter { $0.rating > 0 }
            let average = rated.isEmpty ? "-" : String(format: "%.1f", Double(rated.map(\.rating).reduce(0, +)) / Double(rated.count))
            result.append(("평균 " + title, average))
        }
        if let title = form.countTitle {
            result.append((title, "\(list.map(\.count).reduce(0, +))개"))
        }
        if form.hasReview {
            result.append(("리뷰 시간", durationString(list.map(\.reviewDuration).reduce(0, +))))
            result.append(("리뷰한 문제", "\(list.filter { $0.reviewDuration > 0 }.count)/\(list.count)"))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    CategoryBadge(category: category, font: .title3.bold())
                    Spacer()
                }
                Picker("기간", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(cards, id: \.0) { StatCard(title: $0.0, value: $0.1) }
                }

                if !form.outcomes.isEmpty && form.outcomes != ["성공", "실패"] {
                    countList(title: "결과", items: form.outcomes.map { outcome in
                        (outcome, Double(periodSessions.filter { $0.outcome == outcome }.count))
                    }.filter { $0.1 > 0 }, format: { "\(Int($0))번" })
                }

                if let title = form.labelsTitle {
                    countList(title: title.replacingOccurrences(of: " (여러 개 선택)", with: "") + "별 시간", items: labelTimes,
                              format: { durationString($0) })
                }

                if let title = form.targetTitle {
                    countList(title: title.replacingOccurrences(of: " (선택)", with: "") + "별 시간", items: targetTimes,
                              format: { durationString($0) })
                }

                if form.outcomes == ["성공", "실패"], let ratingTitle = form.ratingTitle {
                    difficultyChart(title: ratingTitle)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("잔디 (최근 26주)").font(.headline)
                    HeatmapView(sessions: sessions, tint: category.color)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle(category.name)
    }

    /// 유형별 시간. 여러 유형을 고른 기록은 각 유형에 시간을 나눠 더한다.
    private var labelTimes: [(String, Double)] {
        var times: [String: Double] = [:]
        for session in periodSessions where !session.labels.isEmpty {
            let share = session.duration / Double(session.labels.count)
            for label in session.labels { times[label, default: 0] += share }
        }
        return times.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    private var targetTimes: [(String, Double)] {
        let grouped = Dictionary(grouping: periodSessions.filter { !$0.target.isEmpty }, by: \.target)
            .mapValues { $0.map(\.duration).reduce(0, +) }
        return grouped.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    /// 이름 · 막대 · 값 목록 (가장 큰 값 기준 막대 길이)
    private func countList(title: String, items: [(String, Double)], format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("이 기간에는 기록이 없어요.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                let maxValue = items.map(\.1).max() ?? 1
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 8) {
                        Text(item.0)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(category.color.opacity(0.8))
                                .frame(width: max(proxy.size.width * item.1 / maxValue, 4))
                        }
                        .frame(height: 10)
                        Text(format(item.1))
                            .font(.callout)
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private struct DifficultyBar: Identifiable {
        let id = UUID()
        let level: Int
        let outcome: String
        let count: Int
    }

    /// 코테: 난이도별 성공/실패 (기존 코테 통계)
    private func difficultyChart(title: String) -> some View {
        let data = (1...5).flatMap { level in
            ["성공", "실패"].map { outcome in
                DifficultyBar(level: level, outcome: outcome,
                              count: periodSessions.filter { $0.rating == level && $0.outcome == outcome }.count)
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(title) 분포 (\(period.rawValue))").font(.headline)
            if periodSessions.isEmpty {
                Text("이 기간에는 기록이 없어요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                Chart(data) { bar in
                    BarMark(
                        x: .value(title, "★\(bar.level)"),
                        y: .value("문제 수", bar.count)
                    )
                    .foregroundStyle(by: .value("결과", bar.outcome))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(["성공": Color.green, "실패": Color.red])
                .frame(height: 130)
            }
        }
    }
}
