import Foundation
import SwiftData

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

/// 문제 하나를 풀고 남긴 기록
@Model
final class SolveRecord {
    var date: Date
    /// 알고리즘 유형 (여러 개)
    var tags: [String]
    /// 난이도 별점 1~5
    var difficulty: Int
    /// 실제로 푼 시간(초). 일시정지한 시간은 제외
    var duration: TimeInterval
    var resultRaw: String
    var memo: String
    /// 코드 리뷰한 시간 합계(초). 여러 번 리뷰하면 더해진다. (기존 기록은 0으로 자동 채워짐)
    var reviewDuration: TimeInterval = 0

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

/// 알고리즘 유형 목록 (기본 목록 + 직접 추가한 유형)
@Model
final class AlgorithmTag {
    @Attribute(.unique) var name: String
    var order: Int

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    static let defaults = [
        "구현", "그리디", "DP", "BFS", "DFS", "백트래킹", "브루트포스",
        "그래프", "최단경로", "트리", "이분탐색", "투 포인터", "정렬",
        "문자열", "해시", "스택/큐", "힙", "자료구조", "수학", "시뮬레이션",
    ]
}
