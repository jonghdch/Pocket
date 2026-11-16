import Foundation
import SwiftData
import WidgetKit

/// 되돌리기에 쓰는 변경 전 모습.
struct TodoSnapshot: Codable, Equatable {
    var id: UUID
    var title: String
    var scheduledAt: Date?
    var hasTime: Bool
    var endAt: Date?
    var isDone: Bool

    init(_ todo: TodoItem) {
        id = todo.id
        title = todo.title
        scheduledAt = todo.scheduledAt
        hasTime = todo.hasTime
        endAt = todo.endAt
        isDone = todo.isDone
    }
}

/// 채팅 메시지에 붙는 결과.
enum ChatPayload: Codable, Equatable {
    struct Result: Codable, Equatable {
        var created: [UUID]
        var before: [TodoSnapshot]
        var touched: [UUID]
        var undone: Bool
    }

    struct Breakdown: Codable, Equatable {
        var todoID: UUID
        var steps: [String]
        var saved: Bool
    }

    /// 여러 날 묶음 미리보기. 저장하면 created 가 채워진다.
    struct Series: Codable, Equatable {
        var draft: SeriesDraft
        var created: [UUID]
        var undone: Bool
    }

    /// 말로 넣은 살 것 미리보기. 저장하면 created 가 채워진다.
    struct Buys: Codable, Equatable {
        var items: [AIPlan.Buy]
        var created: [UUID]
        var undone: Bool
    }

    case result(Result)
    case breakdown(Breakdown)
    case series(Series)
    case buys(Buys)

    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> ChatPayload? {
        data.flatMap { try? JSONDecoder().decode(ChatPayload.self, from: $0) }
    }
}

@MainActor
enum PlanApplier {
    /// 계획을 저장소에 반영한다. 캘린더, 알림은 호출한 쪽에서 TodoSync 로 맞춘다.
    static func apply(_ plan: AIPlan, in context: ModelContext, now: Date = .now) throws -> (ChatPayload.Result, [TodoItem]) {
        var created: [UUID] = []
        var before: [TodoSnapshot] = []
        var touched: [UUID] = []
        var changed: [TodoItem] = []

        for item in plan.create ?? [] {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let start = PlanDate.make(date: item.date, time: item.start_time)
            let todo = TodoItem(
                title: title,
                scheduledAt: start,
                hasTime: start != nil && item.start_time != nil,
                endAt: PlanDate.make(date: item.date, time: item.end_time),
                estimateMinutes: item.estimate_minutes,
                createdAt: now
            )
            context.insert(todo)
            created.append(todo.id)
            changed.append(todo)
        }

        for change in plan.update ?? [] {
            guard let id = UUID(uuidString: change.id) else { continue }
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
            guard let todo = try context.fetch(descriptor).first else { continue }
            before.append(TodoSnapshot(todo))
            touched.append(id)
            if let title = change.title { todo.title = title }
            if change.date != nil || change.start_time != nil {
                let dateText = change.date ?? todo.scheduledAt.map(dayString)
                if let start = PlanDate.make(date: dateText, time: change.start_time) {
                    todo.scheduledAt = start
                    if change.start_time != nil { todo.hasTime = true }
                }
            }
            if let end = change.end_time {
                let dateText = change.date ?? todo.scheduledAt.map(dayString)
                todo.endAt = PlanDate.make(date: dateText, time: end)
            }
            if let done = change.done { todo.setDone(done, now: now) }
            changed.append(todo)
        }

        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return (.init(created: created, before: before, touched: touched, undone: false), changed)
    }

    /// 결과를 되돌린다. 남은 항목은 캘린더, 알림을 맞출 수 있게 돌려준다.
    static func undo(_ result: ChatPayload.Result, in context: ModelContext) throws -> [TodoItem] {
        for id in result.created {
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
            if let todo = try context.fetch(descriptor).first { TodoSync.delete(todo, in: context) }
        }
        var restored: [TodoItem] = []
        for snapshot in result.before {
            let id = snapshot.id
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
            guard let todo = try context.fetch(descriptor).first else { continue }
            todo.title = snapshot.title
            todo.scheduledAt = snapshot.scheduledAt
            todo.hasTime = snapshot.hasTime
            todo.endAt = snapshot.endAt
            todo.setDone(snapshot.isDone)
            restored.append(todo)
        }
        try context.save()
        return restored
    }

    /// AI 에게 넘길 현재 항목 목록. 묶음 항목은 어제부터 7일 뒤까지만 넣어 목록이 넘치지 않게 한다.
    static func describe(_ todos: [TodoItem], now: Date = .now) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let until = calendar.date(byAdding: .day, value: 8, to: today) ?? today
        return todos.filter { todo in
            guard !todo.isDone else { return false }
            guard todo.seriesID != nil, let start = todo.scheduledAt else { return true }
            return start >= from && start < until
        }.prefix(60).map { todo in
            var line = "- id=\(todo.id.uuidString) 제목=\(todo.title)"
            if let start = todo.scheduledAt {
                line += " 날짜=\(dayString(start))"
                if todo.hasTime { line += " 시작=\(Format.clock24(start))" }
                if let end = todo.endAt { line += " 끝=\(Format.clock24(end))" }
            }
            if let series = todo.seriesID { line += " 묶음=\(series.uuidString.prefix(8))" }
            return line
        }.joined(separator: "\n")
    }

    private static func dayString(_ date: Date) -> String { PlanDate.string(from: date) }
}

@MainActor
enum SeriesApplier {
    /// 미리보기에서 확인한 묶음을 날짜별 할 일로 저장한다. 캘린더, 알림은 호출한 쪽에서 맞춘다.
    static func save(_ draft: SeriesDraft, in context: ModelContext, now: Date = .now) throws -> [TodoItem] {
        let series = UUID()
        var created: [TodoItem] = []
        for day in draft.days {
            guard let start = PlanDate.make(date: day.date, time: day.start_time) else { continue }
            let todo = TodoItem(
                title: day.title,
                scheduledAt: start,
                hasTime: day.start_time != nil,
                endAt: day.start_time == nil ? nil : PlanDate.make(date: day.date, time: day.end_time),
                estimateMinutes: day.estimate_minutes,
                createdAt: now
            )
            todo.seriesID = series
            context.insert(todo)
            created.append(todo)
        }
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return created
    }
}

@MainActor
enum BuyApplier {
    static func save(_ items: [AIPlan.Buy], in context: ModelContext, now: Date = .now) throws -> [BuyItem] {
        let saved = items.map { item in
            BuyItem(
                name: item.name, quantity: item.quantity,
                dueDate: PlanDate.make(date: item.due_date, time: nil), store: item.store, createdAt: now)
        }
        for item in saved { context.insert(item) }
        try context.save()
        return saved
    }

    static func undo(_ ids: [UUID], in context: ModelContext) throws {
        for id in ids {
            let descriptor = FetchDescriptor<BuyItem>(predicate: #Predicate { $0.id == id })
            if let item = try context.fetch(descriptor).first { context.delete(item) }
        }
        try context.save()
    }

    /// 산 지 3일이 지난 품목을 지운다. 지운 개수를 돌려준다.
    @discardableResult
    static func purge(in context: ModelContext, now: Date = .now) throws -> Int {
        let bought = try context.fetch(FetchDescriptor<BuyItem>(predicate: #Predicate { $0.isBought }))
        let expired = bought.filter { BuyRules.isExpired($0, now: now) }
        for item in expired { context.delete(item) }
        if !expired.isEmpty { try context.save() }
        return expired.count
    }
}
