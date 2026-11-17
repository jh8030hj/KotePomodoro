import SwiftUI
import SwiftData

/// 설정 창 (⌘, 또는 타이머 화면의 톱니바퀴)
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("목표", systemImage: "target") { GoalSettings() }
            Tab("카테고리", systemImage: "square.grid.2x2") { CategorySettings() }
            Tab("타이머", systemImage: "timer") { TimerSettings() }
        }
        .frame(width: 500, height: 520)
    }
}

// MARK: - 목표

private struct GoalSettings: View {
    @Query(sort: \TaskCategory.order) private var categories: [TaskCategory]

    var body: some View {
        let active = categories.active
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("카테고리").foregroundStyle(.secondary)
                        Text("주간 목표").foregroundStyle(.secondary)
                        Text("일간 목표").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    ForEach(active) { category in
                        @Bindable var category = category
                        GridRow {
                            CategoryBadge(category: category, font: .body)
                            HoursField(title: "\(category.name) 주간 목표", minutes: $category.weeklyGoalMinutes, maxHours: 80)
                            HoursField(title: "\(category.name) 일간 목표", minutes: $category.dailyGoalMinutes, maxHours: 16)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("합계").bold()
                        Text(durationString(TimeInterval(active.map(\.weeklyGoalMinutes).reduce(0, +) * 60)))
                            .monospacedDigit()
                        Text(durationString(TimeInterval(active.map(\.dailyGoalMinutes).reduce(0, +) * 60)))
                            .monospacedDigit()
                    }
                }
            } footer: {
                Text("0이면 목표가 없어요. 통계 탭의 목표 달성 막대와 타이머 화면의 오늘 진행률이 이 값을 써요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 시간 단위(0.5시간 간격)로 입력하고 분으로 저장하는 칸
private struct HoursField: View {
    let title: String
    @Binding var minutes: Int
    let maxHours: Double

    private var hours: Binding<Double> {
        Binding(
            get: { Double(minutes) / 60 },
            set: { minutes = Int((min(max($0, 0), maxHours) * 60).rounded()) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, value: hours, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .textFieldStyle(.roundedBorder)
            Text("시간")
            Stepper(title, value: hours, in: 0...maxHours, step: 0.5)
                .labelsHidden()
        }
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
            Menu {
                ForEach(CategorySymbols.all, id: \.self) { symbol in
                    Button { category.symbol = symbol } label: { Image(systemName: symbol) }
                }
            } label: {
                Image(systemName: category.symbol).foregroundStyle(category.color)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("아이콘")

            TextField("이름", text: $category.name)
                .textFieldStyle(.roundedBorder)

            Menu {
                ForEach(CategoryPalette.names, id: \.self) { name in
                    Button {
                        category.colorName = name
                    } label: {
                        Label(name, systemImage: "circle.fill")
                    }
                }
            } label: {
                Circle().fill(category.color).frame(width: 14, height: 14)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("색")

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
                Text("바꾼 시간은 다음 타이머부터 적용돼요. 알림은 소리 없이 표시돼요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(TimerModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
