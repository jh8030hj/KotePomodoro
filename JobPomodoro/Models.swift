import Foundation
import SwiftData
import SwiftUI

// MARK: - 코테 포모도로 시절 모델 (기존 저장소를 열기 위해 남겨 둔다. 새 기록은 WorkSession에 쌓인다)

/// 문제 풀이 결과
enum SolveResult: String, Codable, CaseIterable, Identifiable {
    case success
    case fail

    var id: Self { self }

    var label: String {
        switch self {
        case .success: "성공"
        case .fail: "실패"
        }
    }
}

/// 코테 포모도로 시절의 문제 기록. 처음 실행할 때 WorkSession으로 옮겨진다.
@Model
final class SolveRecord {
    var date: Date
    var tags: [String]
    var difficulty: Int
    var duration: TimeInterval
    var resultRaw: String
    var memo: String
    var reviewDuration: TimeInterval = 0
    /// WorkSession으로 옮겼는지
    var migrated: Bool = false

    init(date: Date = .now, tags: [String], difficulty: Int, duration: TimeInterval, result: SolveResult, memo: String) {
        self.date = date
        self.tags = tags
        self.difficulty = difficulty
        self.duration = duration
        self.resultRaw = result.rawValue
        self.memo = memo
    }

    var result: SolveResult { SolveResult(rawValue: resultRaw) ?? .success }
}

/// 코테 포모도로 시절의 알고리즘 유형 목록. 처음 실행할 때 SessionLabel로 옮겨진다.
@Model
final class AlgorithmTag {
    @Attribute(.unique) var name: String
    var order: Int

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }
}

// MARK: - 취준 포모도로 모델

/// 취준 카테고리 (코테, 이력서·지원 …). 기록 양식과 타이머 방식은 kind가 정한다.
@Model
final class TaskCategory {
    @Attribute(.unique) var key: String
    var name: String
    var kindRaw: String
    var symbol: String
    var colorName: String
    var order: Int
    var focusMinutes: Int
    var restMinutes: Int
    var weeklyGoalMinutes: Int = 0
    /// 오늘 목표(분). dailyGoalDate가 오늘일 때만 유효하고, 다음 날엔 0으로 본다
    var dailyGoalMinutes: Int = 0
    var dailyGoalDate: Date?
    var isArchived: Bool = false

    init(key: String, name: String, kind: CategoryKind, symbol: String, colorName: String, order: Int,
         focusMinutes: Int, restMinutes: Int, weeklyGoalMinutes: Int = 0) {
        self.key = key
        self.name = name
        self.kindRaw = kind.rawValue
        self.symbol = symbol
        self.colorName = colorName
        self.order = order
        self.focusMinutes = focusMinutes
        self.restMinutes = restMinutes
        self.weeklyGoalMinutes = weeklyGoalMinutes
    }

    /// 오늘 목표(분). 다른 날 정한 값은 무시한다
    var todayGoalMinutes: Int {
        get {
            guard let date = dailyGoalDate, Calendar.current.isDateInToday(date) else { return 0 }
            return dailyGoalMinutes
        }
        set {
            dailyGoalMinutes = newValue
            dailyGoalDate = .now
        }
    }

    var kind: CategoryKind { CategoryKind(rawValue: kindRaw) ?? .custom }
    var form: CategoryForm { kind.form }
    var color: Color { CategoryPalette.color(colorName) }
}

/// 집중한 한 번의 기록 (모든 카테고리 공통). 어떤 칸을 쓰는지는 카테고리 양식(CategoryForm)이 정한다.
@Model
final class WorkSession {
    var date: Date
    var categoryKey: String
    /// 실제로 집중한 시간(초). 휴식·일시정지 제외
    var duration: TimeInterval
    var memo: String = ""
    /// 유형·주제·종류 (여러 개)
    var labels: [String] = []
    /// 별점 1~5 (난이도·자신감·이해도·강도). 0이면 없음
    var rating: Int = 0
    /// 회사·프로젝트·자료 이름
    var target: String = ""
    /// 질문 수·공고 수
    var count: Int = 0
    /// 결과 (성공/실패, 제출 완료 …). 양식의 outcomes 중 하나
    var outcome: String = ""
    /// 코드 리뷰 시간 합계(초)
    var reviewDuration: TimeInterval = 0
    /// 연결된 할 일
    var todoID: UUID?

    init(date: Date = .now, categoryKey: String, duration: TimeInterval) {
        self.date = date
        self.categoryKey = categoryKey
        self.duration = duration
    }
}

/// 카테고리별로 고를 수 있는 유형·주제 목록
@Model
final class SessionLabel {
    var categoryKey: String
    var name: String
    var order: Int

    init(categoryKey: String, name: String, order: Int) {
        self.categoryKey = categoryKey
        self.name = name
        self.order = order
    }
}

/// 할 일. 타이머를 할 일에서 시작하면 기록이 이 할 일에 연결된다.
@Model
final class TodoItem {
    var uid: UUID = UUID()
    var title: String
    var categoryKey: String
    var target: String = ""
    var due: Date?
    var isDone: Bool = false
    var doneAt: Date?
    var createdAt: Date = Date.now

    init(title: String, categoryKey: String, target: String = "", due: Date? = nil) {
        self.title = title
        self.categoryKey = categoryKey
        self.target = target
        self.due = due
    }

    func setDone(_ done: Bool) {
        isDone = done
        doneAt = done ? .now : nil
    }
}

/// 앱이 쓰는 SwiftData 모델 전체
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        SolveRecord.self, AlgorithmTag.self,
        TaskCategory.self, WorkSession.self, SessionLabel.self, TodoItem.self,
    ]
}

// MARK: - 색

enum CategoryPalette {
    static let names = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown", "gray"]

    static func color(_ name: String) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        default: .gray
        }
    }
}
