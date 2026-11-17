import SwiftUI

/// 선택할 수 있는 칩 (유형·주제 등)
struct TagChip: View {
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

/// 카테고리 아이콘 + 이름 칩
struct CategoryBadge: View {
    let category: TaskCategory?
    var font: Font = .caption

    var body: some View {
        Label(category?.name ?? "삭제된 카테고리", systemImage: category?.symbol ?? "questionmark")
            .font(font)
            .foregroundStyle(category?.color ?? .secondary)
    }
}

/// 숫자를 직접 입력하거나 화살표로 조절하는 칸
struct NumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: clamped, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            if !unit.isEmpty { Text(unit) }
            Stepper(title, value: clamped, in: range, step: step)
                .labelsHidden()
        }
    }

    /// 범위를 벗어난 숫자는 최소·최대값으로 맞춘다
    private var clamped: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

/// 시간 단위(0.5시간 간격)로 입력하고 분으로 저장하는 칸
struct HoursField: View {
    let title: String
    @Binding var minutes: Int
    var maxHours: Double = 80

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
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
            Text("시간")
            Stepper(title, value: hours, in: 0...maxHours, step: 0.5)
                .labelsHidden()
        }
    }
}
