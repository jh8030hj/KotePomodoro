import SwiftUI
import SwiftData

/// 설정 창 (⌘, 또는 타이머 화면의 톱니바퀴)
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("카테고리", systemImage: "square.grid.2x2") { CategorySettings() }
            Tab("타이머", systemImage: "timer") { TimerSettings() }
        }
        .frame(width: 500, height: 520)
    }
}

// MARK: - 카테고리

private struct CategorySettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]
    @Query private var sessions: [WorkSession]
    @State private var newName = ""
    @State private var toDelete: TaskCategory?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(categories) { category in
                    CategoryRow(category: category, canDelete: category.kind == .custom) {
                        toDelete = category
                    }
                }
                .onMove(perform: move)
            }
            HStack {
                TextField("새 카테고리 (예: 어학·자격증)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("추가", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            Text("끌어서 순서를 바꿔요. 기본 카테고리는 지우는 대신 숨길 수 있어요 (기록은 남아요).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
        .confirmationDialog(
            "카테고리를 삭제할까요?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            presenting: toDelete
        ) { category in
            Button("삭제", role: .destructive) {
                context.delete(category)
                toDelete = nil
            }
        } message: { category in
            let count = sessions.filter { $0.categoryKey == category.key }.count
            Text(count > 0 ? "이 카테고리의 기록 \(count)개는 남지만 '삭제된 카테고리'로 보여요. 숨기기를 권해요." : "되돌릴 수 없어요.")
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let used = Set(categories.map(\.colorName))
        let color = CategoryPalette.names.first { !used.contains($0) } ?? "gray"
        context.insert(TaskCategory(
            key: UUID().uuidString, name: name, kind: .custom, symbol: "star", colorName: color,
            order: (categories.map(\.order).max() ?? 0) + 1, focusMinutes: 25, restMinutes: 5
        ))
        newName = ""
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = categories
        list.move(fromOffsets: source, toOffset: destination)
        for (index, category) in list.enumerated() { category.order = index }
    }
}

private struct CategoryRow: View {
    @Bindable var category: TaskCategory
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SymbolPickerButton(category: category)

            TextField("이름", text: $category.name)
                .textFieldStyle(.roundedBorder)

            ColorPickerButton(category: category)

            Toggle("숨기기", isOn: $category.isArchived)
                .toggleStyle(.checkbox)

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("삭제")
            }
        }
        .opacity(category.isArchived ? 0.5 : 1)
    }
}

/// 누르면 옆에 아이콘 목록이 격자로 뜬다
private struct SymbolPickerButton: View {
    @Bindable var category: TaskCategory
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: category.symbol)
                .foregroundStyle(category.color)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .help("아이콘 바꾸기")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("아이콘").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6), spacing: 6) {
                    ForEach(CategorySymbols.all, id: \.self) { symbol in
                        Button {
                            category.symbol = symbol
                            isPresented = false
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 34, height: 34)
                                .foregroundStyle(symbol == category.symbol ? Color.white : category.color)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(symbol == category.symbol ? category.color : Color.secondary.opacity(0.1))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
        }
    }
}

/// 누르면 옆에 색 목록이 뜬다
private struct ColorPickerButton: View {
    @Bindable var category: TaskCategory
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Circle().fill(category.color).frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .help("색 바꾸기")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("색").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                    ForEach(CategoryPalette.names, id: \.self) { name in
                        Button {
                            category.colorName = name
                            isPresented = false
                        } label: {
                            Circle()
                                .fill(CategoryPalette.color(name))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if name == category.colorName {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 타이머

private struct TimerSettings: View {
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]

    var body: some View {
        Form {
            Section {
                ForEach(categories.active) { category in
                    @Bindable var category = category
                    LabeledContent {
                        if category.form.timerMode == .stopwatch {
                            Text("스톱워치 (끝나는 시간 없음)").foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 12) {
                                Text("집중")
                                NumberField(title: "집중", value: $category.focusMinutes, range: 1...180, unit: "분")
                                Text("휴식")
                                NumberField(title: "휴식", value: $category.restMinutes, range: 1...60, unit: "분")
                            }
                        }
                    } label: {
                        CategoryBadge(category: category, font: .body)
                    }
                }
            } footer: {
                Text("바꾼 시간은 다음 타이머부터 적용돼요. mac 알림은 소리 없이 표시돼요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PhoneAlertSection()
        }
        .formStyle(.grouped)
    }
}

/// 아이폰 알림 켜기/끄기 (미리 알림 이용)
private struct PhoneAlertSection: View {
    @AppStorage(PhoneAlert.enabledKey) private var enabled = false
    @State private var denied = PhoneAlert.isDenied

    var body: some View {
        Section {
            Toggle("아이폰에도 알림 보내기", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    if newValue {
                        Task {
                            let granted = await PhoneAlert.requestAccess()
                            enabled = granted
                            denied = !granted
                        }
                    } else {
                        PhoneAlert.cancel()
                        enabled = false
                    }
                }
            ))
            if denied {
                HStack {
                    Text("미리 알림 접근이 꺼져 있어요.")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("시스템 설정 열기") { PhoneAlert.openPrivacySettings() }
                }
                .font(.callout)
            }
        } header: {
            Text("아이폰 알림")
        } footer: {
            Text("""
            타이머가 끝나는 시각에 맞춰 '미리 알림'의 '\(PhoneAlert.listTitle)' 목록에 항목을 만들어요. \
            iCloud로 동기화되어 같은 Apple ID의 아이폰·애플워치에서 울리고, 일시정지·취소하면 지워져요. \
            아이폰 소리는 아이폰 설정 → 알림 → 미리 알림에서 정해요.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(TimerModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
