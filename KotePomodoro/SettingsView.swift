import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.focusMinutes) private var focusMinutes = 40
    @AppStorage(SettingsKey.restMinutes) private var restMinutes = 10

    var body: some View {
        Form {
            MinutesField(title: "푸는 시간", value: $focusMinutes, range: 1...180)
            MinutesField(title: "휴식 시간", value: $restMinutes, range: 1...60)
            Text("바꾼 시간은 다음 타이머부터 적용돼요. 알림은 소리 없이 표시돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding(.vertical, 8)
    }
}

/// 숫자를 직접 입력하거나 화살표로 조절하는 분 입력칸
private struct MinutesField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                Text("분")
                Stepper(title, value: clamped, in: range)
                    .labelsHidden()
            }
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

#Preview {
    SettingsView()
}
