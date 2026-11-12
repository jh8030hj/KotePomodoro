import SwiftUI
import SwiftData
import Charts

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "이번 주"
    case month = "이번 달"
    case all = "전체"

    var id: Self { self }
}

struct StatsView: View {
    @Query private var records: [SolveRecord]
    @State private var period: StatsPeriod = .week

    private let calendar = Calendar.current

    private var periodRecords: [SolveRecord] {
        switch period {
        case .all: records
        case .week: records.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
        case .month: records.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
        }
    }

    private var solvedCount: Int { periodRecords.filter { $0.result == .success }.count }

    private var successRate: String {
        guard !periodRecords.isEmpty else { return "-" }
        return "\(Int((Double(solvedCount) / Double(periodRecords.count) * 100).rounded()))%"
    }

    private var totalTime: TimeInterval { periodRecords.map(\.duration).reduce(0, +) }

    /// 기간 안에 푼 문제들의 리뷰 시간 합계 (리뷰 시간은 문제를 푼 날짜 기준으로 묶인다)
    private var reviewTime: TimeInterval { periodRecords.map(\.reviewDuration).reduce(0, +) }

    private var reviewedCount: Int { periodRecords.filter { $0.reviewDuration > 0 }.count }

    private var todayCount: Int {
        records.filter { $0.result == .success && calendar.isDateInToday($0.date) }.count
    }

    /// 성공 기록이 있는 날이 오늘(또는 어제)부터 며칠 연속인지
    private var streak: Int {
        let days = Set(records.filter { $0.result == .success }.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private struct DifficultyBar: Identifiable {
        let id = UUID()
        let level: Int
        let result: SolveResult
        let count: Int
    }

    private var difficultyData: [DifficultyBar] {
        (1...5).flatMap { level in
            SolveResult.allCases.map { result in
                DifficultyBar(
                    level: level,
                    result: result,
                    count: periodRecords.filter { $0.difficulty == level && $0.result == result }.count
                )
            }
        }
    }

    var body: some View {
        // 구역 사이를 Spacer로 띄워서 남는 세로 공간을 고르게 나눈다 (아래만 비지 않게)
        VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("오늘 \(todayCount)문제 풀었어요")
                        .font(.title3.bold())

                    Picker("기간", selection: $period) {
                        ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Spacer(minLength: 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    StatCard(title: "푼 문제", value: "\(solvedCount)개")
                    StatCard(title: "성공률", value: successRate)
                    StatCard(title: "연속 풀이", value: "\(streak)일")
                    StatCard(title: "풀이 시간", value: durationString(totalTime))
                    StatCard(title: "리뷰 시간", value: durationString(reviewTime))
                    StatCard(title: "리뷰한 문제", value: "\(reviewedCount)/\(periodRecords.count)")
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("잔디 (최근 26주, 푼 문제 수)").font(.headline)
                    HeatmapView(records: records)
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("난이도 분포 (\(period.rawValue))").font(.headline)
                    if periodRecords.isEmpty {
                        Text("이 기간에는 기록이 없어요.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        Chart(difficultyData) { bar in
                            BarMark(
                                x: .value("난이도", "★\(bar.level)"),
                                y: .value("문제 수", bar.count)
                            )
                            .foregroundStyle(by: .value("결과", bar.result.label))
                        }
                        .chartForegroundStyleScale(["성공": Color.green, "실패": Color.red])
                        .frame(height: 110)
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
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

struct HeatmapView: View {
    let records: [SolveRecord]
    var weeks = 26

    private let calendar = Calendar.current

    var body: some View {
        let counts = Dictionary(
            grouping: records.filter { $0.result == .success },
            by: { calendar.startOfDay(for: $0.date) }
        ).mapValues(\.count)
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
                            let count = counts[day] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: day > today ? 0 : count))
                                .aspectRatio(1, contentMode: .fit)
                                .help("\(day.formatted(.dateTime.month().day())): \(count)문제")
                        }
                    }
                }
            }
            HStack(spacing: 3) {
                Text("적음").font(.caption2).foregroundStyle(.secondary)
                ForEach([0, 1, 2, 3, 4], id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: n)).frame(width: 10, height: 10)
                }
                Text("많음").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: Color.secondary.opacity(0.15)
        case 1: Color.green.opacity(0.35)
        case 2: Color.green.opacity(0.55)
        case 3: Color.green.opacity(0.75)
        default: Color.green
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [SolveRecord.self, AlgorithmTag.self], inMemory: true)
        .frame(width: 400, height: 550)
}
