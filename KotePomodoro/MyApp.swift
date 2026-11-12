import SwiftUI
import SwiftData

@main
struct MyApp: App {
    @State private var timer = TimerModel()

    init() {
        SettingsKey.registerDefaults()
        Notifier.setup()
    }

    var body: some Scene {
        Window("코테 포모도로", id: "main") {
            ContentView()
                .environment(timer)
        }
        .windowResizability(.contentSize)  // 창 크기 고정 (ContentView 크기에 맞춤)
        // 켤 때마다 항상 화면 왼쪽 위(메뉴바 바로 아래)에 띄운다
        .defaultWindowPlacement { content, context in
            let size = content.sizeThatFits(.unspecified)
            let origin = context.defaultDisplay.visibleRect.origin
            return WindowPlacement(origin, size: size)
        }
        .restorationBehavior(.disabled)  // 지난번 창 위치를 기억하지 않음
        .modelContainer(for: [SolveRecord.self, AlgorithmTag.self])

        Settings {
            SettingsView()
        }
    }
}
