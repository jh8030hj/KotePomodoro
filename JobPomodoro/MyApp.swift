import SwiftUI
import SwiftData

@main
struct MyApp: App {
    @State private var timer = TimerModel()
    @State private var appState = AppState()
    private let container: ModelContainer

    init() {
        Notifier.setup()
        do {
            container = try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("저장소를 열 수 없어요: \(error)")
        }
        DataMigration.run(container.mainContext)
    }

    var body: some Scene {
        Window("취준 포모도로", id: "main") {
            ContentView()
                .environment(timer)
                .environment(appState)
        }
        .windowResizability(.contentSize)  // 창 크기 고정 (ContentView 크기에 맞춤)
        // 켤 때마다 항상 화면 왼쪽 위(메뉴바 바로 아래)에 띄운다
        .defaultWindowPlacement { content, context in
            let size = content.sizeThatFits(.unspecified)
            let origin = context.defaultDisplay.visibleRect.origin
            return WindowPlacement(origin, size: size)
        }
        .restorationBehavior(.disabled)  // 지난번 창 위치를 기억하지 않음
        .modelContainer(container)

        Settings {
            SettingsView()
                .environment(timer)
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable {
    case timer, todo, history, stats
}

/// 탭 사이에서 공유하는 화면 상태 (할 일에서 ▶를 누르면 타이머 탭으로 넘어가는 등)
@Observable
final class AppState {
    var tab: AppTab = .timer
    /// 타이머에서 고른 카테고리 (다음 실행 때도 기억)
    var selectedCategoryKey: String {
        didSet { UserDefaults.standard.set(selectedCategoryKey, forKey: "selectedCategory") }
    }
    /// 타이머에서 고른 할 일 (선택 사항)
    var selectedTodoID: UUID?

    init() {
        selectedCategoryKey = UserDefaults.standard.string(forKey: "selectedCategory") ?? CategoryKind.coding.rawValue
    }
}
