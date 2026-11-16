import AppIntents
import SwiftData
import UserNotifications
import WidgetKit

/// 위젯의 체크 동그라미. 앱을 열지 않고 완료 처리한다.
struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "할 일 완료"

    @Parameter(title: "할 일") var todoID: String

    init() {}
    init(todoID: UUID) { self.todoID = todoID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: todoID) else { return .result() }
        let context = ModelContext(try PocketStore.makeContainer())
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
        if let todo = try context.fetch(descriptor).first {
            todo.setDone(!todo.isDone)
            try context.save()
            if todo.isDone {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [todo.id.uuidString])
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
