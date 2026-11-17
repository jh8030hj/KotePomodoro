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
                .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    todos.isEmpty ? "할 일이 없어요" : "이 카테고리에는 할 일이 없어요",
                    systemImage: "checklist",
                    description: Text("위에서 할 일을 추가하고, ▶를 눌러 바로 타이머를 시작해 보세요.")
                )
            } else {
                let spent = spent
                List {
                    Section("할 일 \(open.count)") {
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
    }

    private var addBar: some View {
        let selectedKey = newCategoryKey ?? appState.selectedCategoryKey
        return VStack(spacing: 8) {
            HStack {
                TextField("할 일 추가 (예: 카카오 자소서 2번 문항)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("추가", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                Picker("카테고리", selection: Binding(get: { selectedKey }, set: { newCategoryKey = $0 })) {
                    ForEach(categories.active) { Label($0.name, systemImage: $0.symbol).tag($0.key) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle("마감", isOn: $newHasDue)
                if newHasDue {
                    DatePicker("마감", selection: $newDue, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
                Picker("보기", selection: $filterKey) {
                    Text("전체").tag(String?.none)
                    ForEach(categories.active) { Text($0.name).tag(Optional($0.key)) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .font(.callout)
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
                        Label(durationString(spent), systemImage: "clock")
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
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(timer.phase != .idle)
                .help(timer.phase == .idle ? "이 할 일로 타이머 준비" : "타이머가 이미 돌고 있어요")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("고치기") { editing = todo }
            Button("삭제", role: .destructive) { context.delete(todo) }
        }
    }

    /// D-3, 오늘, 3일 지남
    private func dueText(_ due: Date) -> some View {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        let text = days == 0 ? "오늘 마감" : days > 0 ? "D-\(days)" : "\(-days)일 지남"
        let color: Color = days < 0 ? .red : days <= 2 ? .orange : .secondary
        return Label(text, systemImage: "calendar")
            .font(.caption.weight(days <= 2 ? .semibold : .regular))
            .foregroundStyle(color)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let key = newCategoryKey ?? appState.selectedCategoryKey
        context.insert(TodoItem(title: title, categoryKey: key, due: newHasDue ? newDue : nil))
        newTitle = ""
    }

    /// 타이머 탭으로 가서 이 할 일과 카테고리를 골라 둔다
    private func startTimer(for todo: TodoItem) {
        appState.selectedCategoryKey = todo.categoryKey
        appState.selectedTodoID = todo.uid
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
