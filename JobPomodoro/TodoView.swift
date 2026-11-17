import SwiftUI
import SwiftData

/// 할 일 목록. ▶를 누르면 그 할 일로 타이머를 시작할 수 있다.
struct TodoView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerModel.self) private var timer
    @Environment(AppState.self) private var appState
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]
    @Query private var sessions: [WorkSession]

    @State private var newTitle = ""
    @State private var newCategoryKey: String?
    @State private var newHasDue = false
    @State private var newDue = Calendar.current.startOfDay(for: .now)
    @State private var filterKey: String?
    @State private var showDone = false
    @State private var editing: TodoItem?
    /// 타이머가 이미 진행 중일 때 '시작'을 누른 할 일
    @State private var busyStart: TodoItem?

    private let calendar = Calendar.current

    private var filtered: [TodoItem] {
        todos.filter { filterKey == nil || $0.categoryKey == filterKey }
    }

    /// 안 끝난 할 일: 마감 빠른 순, 마감 없는 건 뒤로
    private var open: [TodoItem] {
        filtered.filter { !$0.isDone }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.createdAt < b.createdAt
            }
        }
    }

    private var done: [TodoItem] {
        filtered.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// 할 일마다 쓴 시간
    private var spent: [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for session in sessions {
            if let id = session.todoID { result[id, default: 0] += session.duration }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            addBar
                .padding([.horizontal, .top], 12)
            listHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    todos.isEmpty ? "할 일이 없어요" : "이 카테고리에는 할 일이 없어요",
                    systemImage: "checklist",
                    description: Text("위에서 할 일을 추가하고, '시작'을 눌러 바로 타이머를 시작해 보세요.")
                )
            } else {
                let spent = spent
                List {
                    Section("해야 할 일") {
                        ForEach(open) { todo in
                            row(todo, spent: spent[todo.uid] ?? 0)
                        }
                    }
                    if !done.isEmpty {
                        Section(isExpanded: $showDone) {
                            ForEach(done) { todo in
                                row(todo, spent: spent[todo.uid] ?? 0)
                            }
                        } header: {
                            Text("완료 \(done.count)")
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { todo in
            TodoEditSheet(todo: todo)
        }
        .confirmationDialog(
            "타이머가 이미 쓰이고 있어요",
            isPresented: Binding(get: { busyStart != nil }, set: { if !$0 { busyStart = nil } }),
            presenting: busyStart
        ) { todo in
            Button("진행 중인 타이머 보기") {
                appState.tab = .timer
                busyStart = nil
            }
            Button("그만두고 이 할 일 시작", role: .destructive) {
                timer.reset()
                startTimer(for: todo)
                busyStart = nil
            }
            Button("취소", role: .cancel) { busyStart = nil }
        } message: { todo in
            Text("지금 \(timer.statusText)이에요. 그만두면 진행 중인 시간은 기록되지 않아요.")
        }
    }

    /// 위: 새 할 일 추가 칸 (상자로 묶음)
    private var addBar: some View {
        let selectedKey = newCategoryKey ?? appState.selectedCategoryKey
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("할 일 내용 (예: 카카오 자소서 2번 문항)", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("추가", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    Text("카테고리").foregroundStyle(.secondary)
                    Picker("카테고리", selection: Binding(get: { selectedKey }, set: { newCategoryKey = $0 })) {
                        ForEach(categories.active) { Label($0.name, systemImage: $0.symbol).tag($0.key) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 12)
                    Toggle("마감일 정하기", isOn: $newHasDue)
                        .toggleStyle(.checkbox)
                    if newHasDue {
                        DatePicker("마감일", selection: $newDue, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .font(.callout)
            }
            .padding(4)
        } label: {
            Label("새 할 일", systemImage: "plus.circle")
        }
    }

    /// 목록 위: 어떤 카테고리의 할 일을 볼지
    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("목록").font(.headline)
            Text("남은 \(open.count) · 완료 \(done.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("보기").font(.callout).foregroundStyle(.secondary)
            Picker("보기", selection: $filterKey) {
                Text("모든 카테고리").tag(String?.none)
                ForEach(categories.active) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.key)) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func row(_ todo: TodoItem, spent: TimeInterval) -> some View {
        let category = categories.category(todo.categoryKey)
        return HStack(spacing: 10) {
            Button {
                todo.setDone(!todo.isDone)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    CategoryBadge(category: category)
                    if !todo.target.isEmpty {
                        Text(todo.target).font(.caption).foregroundStyle(.secondary)
                    }
                    if let due = todo.due, !todo.isDone {
                        dueText(due)
                    }
                    if spent > 0 {
                        Text("쓴 시간 " + durationString(spent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if !todo.isDone {
                Button {
                    startTimer(for: todo)
                } label: {
                    Label("시작", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("이 할 일로 타이머 시작")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("고치기") { editing = todo }
            Button("삭제", role: .destructive) { context.delete(todo) }
        }
    }

    /// 마감 D-3 (11월 20일), 오늘 마감, 3일 지남
    private func dueText(_ due: Date) -> some View {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        let when = days == 0 ? "오늘 마감" : days > 0 ? "마감 D-\(days)" : "마감 \(-days)일 지남"
        let color: Color = days < 0 ? .red : days <= 2 ? .orange : .secondary
        return Text("\(when) (\(due.formatted(.dateTime.month().day())))")
            .font(.caption.weight(days <= 2 ? .semibold : .regular))
            .foregroundStyle(color)
            .help("마감일")
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let key = newCategoryKey ?? appState.selectedCategoryKey
        context.insert(TodoItem(title: title, categoryKey: key, due: newHasDue ? newDue : nil))
        newTitle = ""
    }

    /// 이 할 일로 바로 타이머를 시작하고 타이머 탭으로 간다. 타이머가 쓰이고 있으면 먼저 묻는다
    private func startTimer(for todo: TodoItem) {
        guard timer.phase == .idle else {
            busyStart = todo
            return
        }
        appState.selectedCategoryKey = todo.categoryKey
        appState.selectedTodoID = todo.uid
        if let category = categories.category(todo.categoryKey) {
            timer.start(category, todoID: todo.uid)
        }
        appState.tab = .timer
    }
}

/// 할 일 고치기
struct TodoEditSheet: View {
    @Bindable var todo: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]

    @State private var hasDue: Bool
    @State private var due: Date

    init(todo: TodoItem) {
        self.todo = todo
        _hasDue = State(initialValue: todo.due != nil)
        _due = State(initialValue: todo.due ?? Calendar.current.startOfDay(for: .now))
    }

    var body: some View {
        Form {
            TextField("할 일", text: $todo.title)
            Picker("카테고리", selection: $todo.categoryKey) {
                ForEach(categories.filter { !$0.isArchived || $0.key == todo.categoryKey }) {
                    Label($0.name, systemImage: $0.symbol).tag($0.key)
                }
            }
            TextField("회사·프로젝트 (선택)", text: $todo.target)
            Toggle("마감일", isOn: $hasDue)
            if hasDue {
                DatePicker("마감", selection: $due, displayedComponents: .date)
            }
            Toggle("완료", isOn: Binding(get: { todo.isDone }, set: { todo.setDone($0) }))
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") {
                    todo.due = hasDue ? due : nil
                    dismiss()
                }
            }
        }
    }
}
