import SwiftUI
import SwiftData

/// 기록 창을 열 때 넘기는 값
struct SessionDraft: Identifiable {
    let id = UUID()
    var categoryKey: String
    var duration: TimeInterval
    var date: Date = .now
    /// 처음 고를 결과 (코테의 성공/실패). nil이면 양식의 첫 번째
    var outcome: String?
    var todoID: UUID?
    /// 타이머 없이 직접 입력하는 기록 (날짜를 고를 수 있다)
    var isManual = false
    /// 이미 있는 기록을 고치는 경우
    var editing: WorkSession?

    static func edit(_ session: WorkSession) -> SessionDraft {
        SessionDraft(categoryKey: session.categoryKey, duration: session.duration, date: session.date,
                     outcome: session.outcome, todoID: session.todoID, isManual: true, editing: session)
    }
}

/// 카테고리 양식에 맞춰 기록을 남기는 창
struct SessionSheet: View {
    let draft: SessionDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]
    @Query(sort: \SessionLabel.order) private var allLabels: [SessionLabel]
    @Query(sort: \TodoItem.createdAt) private var todos: [TodoItem]

    @State private var categoryKey: String
    @State private var date: Date
    @State private var minutes: Int
    @State private var outcome: String
    @State private var selected: Set<String>
    @State private var rating: Int
    @State private var target: String
    @State private var count: Int
    @State private var memo: String
    @State private var todoID: UUID?
    @State private var markTodoDone = false
    @State private var newLabel = ""
    @State private var confirmDelete = false

    init(draft: SessionDraft, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        let session = draft.editing
        let form = (CategoryKind(rawValue: draft.categoryKey) ?? .custom).form
        _categoryKey = State(initialValue: draft.categoryKey)
        _date = State(initialValue: draft.date)
        _minutes = State(initialValue: Int((draft.duration / 60).rounded()))
        _outcome = State(initialValue: draft.outcome ?? form.outcomes.first ?? "")
        _selected = State(initialValue: Set(session?.labels ?? []))
        _rating = State(initialValue: session?.rating ?? 3)
        _target = State(initialValue: session?.target ?? "")
        _count = State(initialValue: session?.count ?? 0)
        _memo = State(initialValue: session?.memo ?? "")
        _todoID = State(initialValue: draft.todoID)
    }

    private var category: TaskCategory? { categories.category(categoryKey) }
    private var form: CategoryForm { category?.form ?? CategoryKind.custom.form }
    private var labels: [SessionLabel] { allLabels.filter { $0.categoryKey == categoryKey } }
    private var linkedTodo: TodoItem? { todoID.flatMap { id in todos.first { $0.uid == id } } }

    /// 이 카테고리에서 연결할 수 있는 할 일 (안 끝난 것 + 이미 연결된 것)
    private var todoChoices: [TodoItem] {
        todos.filter { $0.categoryKey == categoryKey && (!$0.isDone || $0.uid == todoID) }
    }

    private var canSave: Bool {
        (!form.requiresLabel || !selected.isEmpty) && minutes >= 0 && (minutes > 0 || draft.duration >= 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !form.outcomes.isEmpty {
                        Picker("결과", selection: $outcome) {
                            ForEach(form.outcomes, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let title = form.labelsTitle {
                        section(title) { labelPicker }
                    }

                    if let title = form.ratingTitle {
                        section(title) { StarRating(value: $rating) }
                    }

                    if let title = form.targetTitle {
                        section(title) {
                            TextField(form.targetPlaceholder, text: $target)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let title = form.countTitle {
                        section(title) {
                            NumberField(title: title, value: $count, range: 0...999, unit: "개")
                        }
                    }

                    if !todoChoices.isEmpty {
                        section("할 일") {
                            Picker("할 일", selection: $todoID) {
                                Text("연결 안 함").tag(UUID?.none)
                                ForEach(todoChoices) { Text($0.title).tag(Optional($0.uid)) }
                            }
                            .labelsHidden()
                            if let todo = linkedTodo, !todo.isDone {
                                Toggle("이 할 일을 완료로 표시", isOn: $markTodoDone)
                            }
                        }
                    }

                    section("메모") {
                        TextEditor(text: $memo)
                            .font(.body)
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 440)

            footer
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: categoryKey) { _, _ in
            selected = []
            outcome = form.outcomes.first ?? ""
            if linkedTodo?.categoryKey != categoryKey { todoID = nil }
        }
        .onChange(of: todoID) { _, _ in
            if target.isEmpty, let todo = linkedTodo { target = todo.target }
        }
        .onAppear {
            if target.isEmpty, let todo = linkedTodo { target = todo.target }
        }
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) {
                if let session = draft.editing { context.delete(session) }
                onSave()
            }
        } message: {
            Text("삭제한 기록은 되돌릴 수 없고, 통계에서도 빠져요.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.editing == nil ? "기록 남기기" : "기록 고치기").font(.title2.bold())
                Spacer()
                Picker("카테고리", selection: $categoryKey) {
                    ForEach(categories.filter { !$0.isArchived || $0.key == categoryKey }) { category in
                        Label(category.name, systemImage: category.symbol).tag(category.key)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 12) {
                if draft.isManual {
                    DatePicker("날짜", selection: $date, in: ...Date.now)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
                Image(systemName: "clock").foregroundStyle(.secondary)
                NumberField(title: "시간", value: $minutes, range: 0...600, step: 5, unit: "분")
            }
        }
    }

    private var footer: some View {
        HStack {
            if draft.editing != nil {
                Button("삭제", role: .destructive) { confirmDelete = true }
            }
            if form.requiresLabel && selected.isEmpty {
                Text("유형을 하나 이상 골라 주세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("취소", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("저장", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    @ViewBuilder
    private var labelPicker: some View {
        FlowLayout(spacing: 6) {
            ForEach(labels) { label in
                TagChip(name: label.name, isSelected: selected.contains(label.name)) {
                    if selected.contains(label.name) { selected.remove(label.name) } else { selected.insert(label.name) }
                }
                .contextMenu {
                    Button("선택지 삭제", role: .destructive) {
                        selected.remove(label.name)
                        context.delete(label)
                    }
                }
            }
        }
        HStack {
            TextField("새 선택지 추가", text: $newLabel)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addLabel)
            Button("추가", action: addLabel)
                .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func addLabel() {
        let name = newLabel.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !labels.contains(where: { $0.name == name }) {
            context.insert(SessionLabel(categoryKey: categoryKey, name: name, order: (labels.map(\.order).max() ?? 0) + 1))
        }
        selected.insert(name)
        newLabel = ""
    }

    private func save() {
        // 분을 고치지 않았으면 초 단위까지 정확한 원래 시간을 쓴다
        let originalMinutes = Int((draft.duration / 60).rounded())
        let duration = minutes == originalMinutes && draft.duration > 0 ? draft.duration : TimeInterval(minutes * 60)

        let session = draft.editing ?? WorkSession(date: date, categoryKey: categoryKey, duration: duration)
        session.date = date
        session.categoryKey = categoryKey
        session.duration = duration
        // 선택지 목록 순서대로 저장 (목록에서 지운 선택지도 남긴다)
        let ordered = labels.map(\.name).filter { selected.contains($0) }
        session.labels = ordered + selected.subtracting(ordered).sorted()
        session.rating = form.ratingTitle == nil ? 0 : rating
        session.target = form.targetTitle == nil ? "" : target.trimmingCharacters(in: .whitespaces)
        session.count = form.countTitle == nil ? 0 : count
        session.outcome = form.outcomes.isEmpty ? "" : outcome
        session.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        session.todoID = todoID
        if draft.editing == nil { context.insert(session) }
        if markTodoDone { linkedTodo?.setDone(true) }
        onSave()
    }
}
