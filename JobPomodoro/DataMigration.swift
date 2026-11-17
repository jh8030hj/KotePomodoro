import Foundation
import SwiftData

/// 앱을 켤 때마다 실행된다. 이미 된 일은 건너뛰므로 여러 번 돌아도 안전하다.
/// (코테 포모도로 저장소를 나중에 복사해 넣어도 다음 실행에서 옮겨진다)
enum DataMigration {
    static func run(_ context: ModelContext) {
        // 선택지 기본값은 카테고리를 처음 만들 때만 넣는다 (사용자가 다 지워도 되살리지 않게)
        if seedCategories(context) { seedLabels(context) }
        migrateSolveRecords(context)
        try? context.save()
    }

    /// 카테고리가 하나도 없으면 기본 카테고리를 만들고 true
    private static func seedCategories(_ context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<TaskCategory>())) ?? 0
        guard count == 0 else { return false }
        for (index, item) in DefaultCategory.all.enumerated() {
            context.insert(TaskCategory(
                key: item.kind.rawValue, name: item.name, kind: item.kind, symbol: item.symbol,
                colorName: item.color, order: index, focusMinutes: item.focus, restMinutes: item.rest,
                weeklyGoalMinutes: item.weeklyGoalHours * 60
            ))
        }
        return true
    }

    /// 기본 카테고리마다 기본 선택지를 넣는다
    private static func seedLabels(_ context: ModelContext) {
        let labels = (try? context.fetch(FetchDescriptor<SessionLabel>())) ?? []
        let keysWithLabels = Set(labels.map(\.categoryKey))
        for kind in CategoryKind.allCases where kind != .custom && !keysWithLabels.contains(kind.rawValue) {
            for (index, name) in kind.form.defaultLabels.enumerated() {
                context.insert(SessionLabel(categoryKey: kind.rawValue, name: name, order: index))
            }
        }
    }

    /// 코테 포모도로의 문제 기록·알고리즘 유형을 새 모델로 옮긴다 (원본은 남겨 둔다)
    private static func migrateSolveRecords(_ context: ModelContext) {
        let coding = CategoryKind.coding.rawValue

        let tags = (try? context.fetch(FetchDescriptor<AlgorithmTag>(sortBy: [SortDescriptor(\.order)]))) ?? []
        if !tags.isEmpty {
            let labels = (try? context.fetch(FetchDescriptor<SessionLabel>())) ?? []
            var known = Set(labels.filter { $0.categoryKey == coding }.map(\.name))
            var next = (labels.filter { $0.categoryKey == coding }.map(\.order).max() ?? -1) + 1
            for tag in tags where !known.contains(tag.name) {
                context.insert(SessionLabel(categoryKey: coding, name: tag.name, order: next))
                known.insert(tag.name)
                next += 1
            }
        }

        let pending = (try? context.fetch(FetchDescriptor<SolveRecord>(predicate: #Predicate { !$0.migrated }))) ?? []
        for record in pending {
            let session = WorkSession(date: record.date, categoryKey: coding, duration: record.duration)
            session.labels = record.tags
            session.rating = record.difficulty
            session.outcome = record.result.label
            session.memo = record.memo
            session.reviewDuration = record.reviewDuration
            context.insert(session)
            record.migrated = true
        }
    }
}
