import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @Query private var tags: [AlgorithmTag]

    var body: some View {
        TabView {
            Tab("타이머", systemImage: "timer") {
                TimerView()
            }
            Tab("기록", systemImage: "list.bullet") {
                HistoryView()
            }
            Tab("통계", systemImage: "chart.bar") {
                StatsView()
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            timer.openMainWindow = { [openWindow] in openWindow(id: "main") }
            seedTagsIfNeeded()
        }
    }

    private func seedTagsIfNeeded() {
        guard tags.isEmpty else { return }
        for (index, name) in AlgorithmTag.defaults.enumerated() {
            context.insert(AlgorithmTag(name: name, order: index))
        }
    }
}

#Preview {
    ContentView()
        .environment(TimerModel())
        .modelContainer(for: [SolveRecord.self, AlgorithmTag.self], inMemory: true)
}
