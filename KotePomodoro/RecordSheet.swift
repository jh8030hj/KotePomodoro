import SwiftUI
import SwiftData

struct RecordSheet: View {
    let duration: TimeInterval
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \AlgorithmTag.order) private var tags: [AlgorithmTag]

    @State private var result: SolveResult
    @State private var selected: Set<String> = []
    @State private var difficulty = 3
    @State private var memo = ""
    @State private var newTag = ""

    init(duration: TimeInterval, initialResult: SolveResult, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.duration = duration
        self.onSave = onSave
        self.onCancel = onCancel
        _result = State(initialValue: initialResult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("문제 기록").font(.title2.bold())
                Spacer()
                Label(durationString(duration), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

            Picker("결과", selection: $result) {
                ForEach(SolveResult.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            section("알고리즘 유형 (여러 개 선택)") {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        TagChip(name: tag.name, isSelected: selected.contains(tag.name)) {
                            toggle(tag.name)
                        }
                        .contextMenu {
                            Button("유형 삭제", role: .destructive) {
                                selected.remove(tag.name)
                                context.delete(tag)
                            }
                        }
                    }
                }
                HStack {
                    TextField("새 유형 추가", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)
                    Button("추가", action: addTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            section("난이도") {
                StarRating(value: $difficulty)
            }

            section("메모") {
                TextEditor(text: $memo)
                    .font(.body)
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                if selected.isEmpty {
                    Text("유형을 하나 이상 골라 주세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("취소", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func toggle(_ name: String) {
        if selected.contains(name) {
            selected.remove(name)
        } else {
            selected.insert(name)
        }
    }

    private func addTag() {
        let name = newTag.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !tags.contains(where: { $0.name == name }) {
            context.insert(AlgorithmTag(name: name, order: (tags.map(\.order).max() ?? 0) + 1))
        }
        selected.insert(name)
        newTag = ""
    }

    private func save() {
        let ordered = tags.map(\.name).filter { selected.contains($0) }
        context.insert(SolveRecord(
            tags: ordered,
            difficulty: difficulty,
            duration: duration,
            result: result,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        onSave()
    }
}

private struct TagChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StarRating: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    value = star
                } label: {
                    Image(systemName: star <= value ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 줄바꿈되는 칩 배치
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
