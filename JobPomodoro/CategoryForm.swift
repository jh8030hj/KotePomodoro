import Foundation

/// 카테고리 종류. 기록 양식과 타이머 방식을 정한다.
enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case coding, application, research, interview, project, study, exercise, custom

    var id: Self { self }

    var form: CategoryForm {
        switch self {
        case .coding:
            CategoryForm(
                labelsTitle: "알고리즘 유형 (여러 개 선택)", requiresLabel: true,
                ratingTitle: "난이도",
                outcomes: ["성공", "실패"],
                hasReview: true,
                startTitle: "문제 풀기 시작", runningTitle: "문제 푸는 중",
                defaultLabels: [
                    "구현", "그리디", "DP", "BFS", "DFS", "백트래킹", "브루트포스",
                    "그래프", "최단경로", "트리", "이분탐색", "투 포인터", "정렬",
                    "문자열", "해시", "스택/큐", "힙", "자료구조", "수학", "시뮬레이션",
                ]
            )
        case .application:
            CategoryForm(
                labelsTitle: "작업",
                targetTitle: "회사·직무", targetPlaceholder: "예: 카카오 서버 개발",
                outcomes: ["작성 중", "제출 완료"],
                defaultLabels: ["이력서", "자소서", "포트폴리오", "지원서 제출"]
            )
        case .research:
            CategoryForm(
                labelsTitle: "활동",
                targetTitle: "회사", targetPlaceholder: "예: 토스",
                countTitle: "찾은 공고 수",
                outcomes: ["관심", "지원 예정", "패스"],
                defaultLabels: ["기업 리서치", "공고 탐색", "현직자 후기", "기술 블로그"]
            )
        case .interview:
            CategoryForm(
                labelsTitle: "종류",
                ratingTitle: "자신감",
                targetTitle: "회사 (선택)", targetPlaceholder: "예: 네이버",
                countTitle: "연습한 질문 수",
                defaultLabels: ["인성", "기술", "PT", "모의면접", "자기소개"]
            )
        case .project:
            CategoryForm(
                labelsTitle: "한 일",
                targetTitle: "프로젝트", targetPlaceholder: "예: 취준 포모도로",
                outcomes: ["진행 중", "완료"],
                defaultLabels: ["기능 개발", "버그 수정", "리팩터링", "문서", "배포"]
            )
        case .study:
            CategoryForm(
                labelsTitle: "주제",
                ratingTitle: "이해도",
                targetTitle: "자료", targetPlaceholder: "예: 책·강의 이름",
                defaultLabels: ["운영체제", "네트워크", "데이터베이스", "자료구조", "Java", "Spring", "시스템 설계"]
            )
        case .exercise:
            CategoryForm(
                labelsTitle: "종류",
                ratingTitle: "강도",
                timerMode: .stopwatch,
                startTitle: "운동 시작", runningTitle: "운동 중",
                defaultLabels: ["유산소", "근력", "스트레칭", "산책"]
            )
        case .custom:
            CategoryForm(labelsTitle: "태그")
        }
    }
}

enum TimerMode {
    /// 집중 시간이 끝나면 추가 시간/휴식을 고르는 포모도로
    case pomodoro
    /// 끝나는 시간 없이 재는 스톱워치 (운동)
    case stopwatch
}

/// 카테고리별 기록 양식. 제목이 nil인 칸은 보이지 않는다.
struct CategoryForm {
    var labelsTitle: String?
    var requiresLabel = false
    var ratingTitle: String?
    var targetTitle: String?
    var targetPlaceholder = ""
    var countTitle: String?
    /// 결과 선택지. 비어 있으면 결과 칸이 없다. 첫 번째가 기본값
    var outcomes: [String] = []
    /// 코드 리뷰 스톱워치를 쓰는지 (코테)
    var hasReview = false
    var timerMode: TimerMode = .pomodoro
    var startTitle = "집중 시작"
    var runningTitle = "집중하는 중"
    var defaultLabels: [String] = []
}

/// 처음 실행할 때 만들어지는 기본 카테고리
struct DefaultCategory {
    let kind: CategoryKind
    let name: String
    let symbol: String
    let color: String
    let focus: Int
    let rest: Int
    let weeklyGoalHours: Int

    static let all: [DefaultCategory] = [
        .init(kind: .coding, name: "코테", symbol: "chevron.left.forwardslash.chevron.right", color: "red", focus: 40, rest: 10, weeklyGoalHours: 10),
        .init(kind: .application, name: "이력서·지원", symbol: "doc.text", color: "blue", focus: 25, rest: 5, weeklyGoalHours: 5),
        .init(kind: .research, name: "기업 분석·공고", symbol: "building.2", color: "teal", focus: 25, rest: 5, weeklyGoalHours: 3),
        .init(kind: .interview, name: "면접 연습", symbol: "person.2.wave.2", color: "purple", focus: 25, rest: 5, weeklyGoalHours: 3),
        .init(kind: .project, name: "개인 프로젝트", symbol: "hammer", color: "orange", focus: 50, rest: 10, weeklyGoalHours: 10),
        .init(kind: .study, name: "관련 공부", symbol: "book", color: "indigo", focus: 25, rest: 5, weeklyGoalHours: 7),
        .init(kind: .exercise, name: "운동", symbol: "figure.run", color: "green", focus: 60, rest: 0, weeklyGoalHours: 3),
    ]
}

/// 카테고리를 고를 때 보여주는 아이콘 후보
enum CategorySymbols {
    static let all = [
        "chevron.left.forwardslash.chevron.right", "doc.text", "building.2", "person.2.wave.2",
        "hammer", "book", "figure.run", "pencil", "lightbulb", "globe", "music.note",
        "character.book.closed", "graduationcap", "briefcase", "star", "heart",
    ]
}
