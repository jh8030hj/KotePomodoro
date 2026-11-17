import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.tab) {
            Tab("타이머", systemImage: "timer", value: AppTab.timer) {
                TimerView()
            }
            Tab("할 일", systemImage: "checklist", value: AppTab.todo) {
                TodoView()
            }
            Tab("기록", systemImage: "list.bullet", value: AppTab.history) {
                HistoryView()
            }
            Tab("통계", systemImage: "chart.bar", value: AppTab.stats) {
                StatsView()
            }
        }
        .frame(width: 440, height: 660)
        .onAppear {
            timer.openMainWindow = { [openWindow] in openWindow(id: "main") }
        }
    }
}

/// 카테고리 key로 카테고리 찾기
extension Array where Element == TaskCategory {
    func category(_ key: String) -> TaskCategory? {
        first { $0.key == key }
    }

    /// 보관하지 않은 카테고리 (순서대로)
    var active: [TaskCategory] {
        filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }
}

#Preview {
    ContentView()
        .environment(TimerModel())
        .environment(AppState())
        .modelContainer(for: AppSchema.models, inMemory: true)
}
