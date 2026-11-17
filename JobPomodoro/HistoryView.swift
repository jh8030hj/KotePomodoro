import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkSession.date, order: .reverse) private var sessions: [WorkSession]
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]

    @State private var search = ""
    @State private var filterKey: String?
    @State private var sessionToDelete: WorkSession?
    @State private var reviewing: WorkSession?
    @State private var draft: SessionDraft?

    private var filtered: [WorkSession] {
        sessions.filter { session in
            let categoryOK = filterKey == nil || session.categoryKey == filterKey
            let searchOK = search.isEmpty
                || session.labels.contains { $0.localizedCaseInsensitiveContains(search) }
                || session.memo.localizedCaseInsensitiveContains(search)
                || session.target.localizedCaseInsensitiveContains(search)
            return categoryOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("유형·회사·메모 검색", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("카테고리", selection: $filterKey) {
                    Text("전체").tag(String?.none)
                    ForEach(categories) { Text($0.name).tag(Optional($0.key)) }
                }
                .labelsHidden()
                .fixedSize()
                Button {
                    draft = SessionDraft(categoryKey: filterKey ?? categories.active.first?.key ?? CategoryKind.coding.rawValue,
                                         duration: 0, isManual: true)
                } label: {
                    Image(systemName: "plus")
                }
                .help("타이머 없이 기록 추가")
            }
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    sessions.isEmpty ? "아직 기록이 없어요" : "검색 결과가 없어요",
                    systemImage: "tray",
                    description: Text(sessions.isEmpty ? "타이머를 끝내고 기록하면 여기에 쌓여요." : "다른 검색어나 카테고리를 골라 보세요.")
                )
            } else {
                List {
                    ForEach(filtered) { session in
                        let category = categories.category(session.categoryKey)
                        SessionRow(session: session, category: category) { reviewing = session }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { draft = .edit(session) }
                            .contextMenu {
                                Button("고치기") { draft = .edit(session) }
                                if category?.form.hasReview == true {
                                    Button("코드 리뷰 시작") { reviewing = session }
                                }
                                Button("기록 삭제", role: .destructive) {
                                    sessionToDelete = session
                                }
                            }
                    }
                }
            }
        }
        .sheet(item: $reviewing) { session in
            ReviewSheet(session: session)
        }
        .sheet(item: $draft) { item in
            SessionSheet(draft: item, onSave: { draft = nil }, onCancel: { draft = nil })
        }
        // 실수로 지우지 않게 한 번 더 묻는다 (되돌릴 수 없음)
        .confirmationDialog(
            "이 기록을 삭제할까요?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("삭제", role: .destructive) {
                context.delete(session)
                sessionToDelete = nil
            }
            Button("취소", role: .cancel) { sessionToDelete = nil }
        } message: { _ in
            Text("삭제한 기록은 되돌릴 수 없고, 통계에서도 빠져요.")
        }
    }
}

private struct SessionRow: View {
    let session: WorkSession
    let category: TaskCategory?
    let onReview: () -> Void

    private var form: CategoryForm { category?.form ?? CategoryKind.custom.form }

    private var headline: String {
        if !session.labels.isEmpty { return session.labels.joined(separator: ", ") }
        if !session.target.isEmpty { return session.target }
        return category?.name ?? "기록"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category?.symbol ?? "questionmark")
                .foregroundStyle(category?.color ?? .secondary)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(durationString(session.duration)).foregroundStyle(.secondary)
                    if !session.target.isEmpty && !session.labels.isEmpty {
                        Text(session.target).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if form.ratingTitle != nil && session.rating > 0 {
                        Text(starString(session.rating)).foregroundStyle(.yellow)
                    }
                    if let title = form.countTitle, session.count > 0 {
                        Text("\(title.replacingOccurrences(of: " 수", with: "")) \(session.count)개").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if !session.memo.isEmpty {
                    Text(session.memo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(session.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !session.outcome.isEmpty {
                    Text(session.outcome)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(outcomeColor)
                }

                if form.hasReview {
                    // 리뷰 시간 표시 + 리뷰 스톱워치 시작
                    Button(action: onReview) {
                        Label(
                            session.reviewDuration > 0 ? "리뷰 " + durationString(session.reviewDuration) : "리뷰 전",
                            systemImage: session.reviewDuration > 0 ? "checkmark.seal.fill" : "stopwatch"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(session.reviewDuration > 0 ? .blue : .secondary)
                    .help("코드 리뷰 스톱워치 시작")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var outcomeColor: Color {
        switch session.outcome {
        case "성공", "제출 완료", "완료", "지원 예정": .green
        case "실패", "패스": .red
        default: .secondary
        }
    }
}

/// 코드 리뷰 시간을 재는 스톱워치. 완료하면 기록의 리뷰 시간에 더해진다.
struct ReviewSheet: View {
    let session: WorkSession
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
                Text(session.labels.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(clockString(elapsed(at: context.date).rounded(.down)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(startedAt == nil ? .secondary : .primary)

                if session.reviewDuration > 0 {
                    Text("이전 리뷰 " + durationString(session.reviewDuration) + "에 더해져요")
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
            session.reviewDuration += total.rounded(.down)
        }
        dismiss()
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
