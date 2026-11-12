import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SolveRecord.date, order: .reverse) private var records: [SolveRecord]

    @State private var search = ""
    @State private var filter: SolveResult?
    @State private var recordToDelete: SolveRecord?
    @State private var reviewing: SolveRecord?

    private var filtered: [SolveRecord] {
        records.filter { record in
            let resultOK = filter == nil || record.result == filter
            let searchOK = search.isEmpty
                || record.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                || record.memo.localizedCaseInsensitiveContains(search)
            return resultOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("유형·메모 검색", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("결과", selection: $filter) {
                    Text("전체").tag(SolveResult?.none)
                    ForEach(SolveResult.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    records.isEmpty ? "아직 기록이 없어요" : "검색 결과가 없어요",
                    systemImage: "tray",
                    description: Text(records.isEmpty ? "문제를 풀고 기록하면 여기에 쌓여요." : "다른 검색어나 필터를 써 보세요.")
                )
            } else {
                List {
                    ForEach(filtered) { record in
                        RecordRow(record: record) { reviewing = record }
                            .contextMenu {
                                Button("코드 리뷰 시작") { reviewing = record }
                                Button("기록 삭제", role: .destructive) {
                                    recordToDelete = record
                                }
                            }
                    }
                }
            }
        }
        .sheet(item: $reviewing) { record in
            ReviewSheet(record: record)
        }
        // 실수로 지우지 않게 한 번 더 묻는다 (되돌릴 수 없음)
        .confirmationDialog(
            "이 기록을 삭제할까요?",
            isPresented: Binding(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            ),
            presenting: recordToDelete
        ) { record in
            Button("삭제", role: .destructive) {
                context.delete(record)
                recordToDelete = nil
            }
            Button("취소", role: .cancel) { recordToDelete = nil }
        } message: { _ in
            Text("삭제한 기록은 되돌릴 수 없고, 통계에서도 빠져요.")
        }
    }
}

private struct RecordRow: View {
    let record: SolveRecord
    let onReview: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.result == .success ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.tags.joined(separator: ", "))
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(starString(record.difficulty)).foregroundStyle(.yellow)
                    Text(durationString(record.duration)).foregroundStyle(.secondary)
                }
                .font(.callout)
                if !record.memo.isEmpty {
                    Text(record.memo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(record.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 리뷰 시간 표시 + 리뷰 스톱워치 시작
                Button(action: onReview) {
                    Label(
                        record.reviewDuration > 0 ? "리뷰 " + durationString(record.reviewDuration) : "리뷰 전",
                        systemImage: record.reviewDuration > 0 ? "checkmark.seal.fill" : "stopwatch"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(record.reviewDuration > 0 ? .blue : .secondary)
                .help("코드 리뷰 스톱워치 시작")
            }
        }
        .padding(.vertical, 4)
    }
}

/// 코드 리뷰 시간을 재는 스톱워치. 완료하면 기록의 리뷰 시간에 더해진다.
struct ReviewSheet: View {
    let record: SolveRecord
    @Environment(\.dismiss) private var dismiss

    @State private var accumulated: TimeInterval = 0
    @State private var startedAt: Date? = .now  // 열자마자 시작

    private func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(spacing: 14) {
                Text("코드 리뷰").font(.title2.bold())
                Text(record.tags.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(clockString(elapsed(at: context.date).rounded(.down)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(startedAt == nil ? .secondary : .primary)

                if record.reviewDuration > 0 {
                    Text("이전 리뷰 " + durationString(record.reviewDuration) + "에 더해져요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        toggle()
                    } label: {
                        Label(startedAt == nil ? "계속" : "일시정지",
                              systemImage: startedAt == nil ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        finish()
                    } label: {
                        Label("리뷰 완료", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)

                Button("기록하지 않고 닫기", role: .cancel) { dismiss() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 320)
        }
    }

    private func toggle() {
        if let start = startedAt {
            accumulated += Date().timeIntervalSince(start)
            startedAt = nil
        } else {
            startedAt = .now
        }
    }

    private func finish() {
        let total = elapsed(at: .now)
        if total >= 1 {
            record.reviewDuration += total.rounded(.down)
        }
        dismiss()
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [SolveRecord.self, AlgorithmTag.self], inMemory: true)
}
