import EventKit
import Network
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

enum SettingKey {
    static let onboarded = "onboarded"
    static let calendar = "calendarEnabled"
    static let notifications = "notificationsEnabled"
    static let defaultTimer = "defaultTimerMinutes"
}

/// iOS 캘린더. 날짜와 시간이 있는 할 일만 넣는다.
enum CalendarService {
    private static let store = EKEventStore()

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: SettingKey.calendar) as? Bool ?? true }
    static var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// 실패하면 false. 앱 안의 저장은 이미 끝난 뒤라 일정은 사라지지 않는다.
    @MainActor
    @discardableResult
    static func sync(_ todo: TodoItem) async -> Bool {
        guard isEnabled else { return true }
        guard todo.isEvent, !todo.isDone, let start = todo.scheduledAt else {
            remove(todo)
            return true
        }
        guard await requestAccess(), let calendar = store.defaultCalendarForNewEvents else { return false }
        let event = todo.calendarEventID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        if event.calendar == nil { event.calendar = calendar }
        event.title = todo.title
        event.startDate = start
        event.endDate = todo.endAt ?? start.addingTimeInterval(TimeInterval((todo.estimateMinutes ?? 60) * 60))
        event.notes = todo.note.isEmpty ? nil : todo.note
        do {
            try store.save(event, span: .thisEvent)
            todo.calendarEventID = event.eventIdentifier
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func remove(_ todo: TodoItem) {
        guard let id = todo.calendarEventID else { return }
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess, let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent)
        }
        todo.calendarEventID = nil
    }
}

enum NotificationService {
    private static var center: UNUserNotificationCenter { .current() }
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: SettingKey.notifications) as? Bool ?? true }

    static func requestAccess() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    @MainActor
    static func sync(_ todo: TodoItem) {
        let id = todo.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isEnabled, !todo.isDone, let start = todo.scheduledAt, let minutes = todo.alertMinutesBefore else { return }
        let fire = start.addingTimeInterval(TimeInterval(-minutes * 60))
        guard fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.body = todo.hasTime ? Format.clock(start) : Format.day(start)
        content.sound = .default
        content.userInfo = ["todo": id]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func scheduleTimerEnd(title: String, after seconds: Int) {
        cancelTimerEnd()
        guard isEnabled, seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "시간이 다 됐어요"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: "focus-timer", content: content, trigger: trigger))
    }

    static func cancelTimerEnd() {
        center.removePendingNotificationRequests(withIdentifiers: ["focus-timer"])
    }

    @MainActor
    static func cancel(_ todo: TodoItem) {
        center.removePendingNotificationRequests(withIdentifiers: [todo.id.uuidString])
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "pocket.network"))
    }

    deinit { monitor.cancel() }
}

/// 할 일을 저장한 뒤 캘린더, 알림, 위젯을 함께 맞춘다.
@MainActor
enum TodoSync {
    /// 캘린더에 못 넣었으면 false.
    @discardableResult
    static func afterChange(_ todo: TodoItem, in context: ModelContext) async -> Bool {
        NotificationService.sync(todo)
        let ok = await CalendarService.sync(todo)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return ok
    }

    static func delete(_ todo: TodoItem, in context: ModelContext) {
        NotificationService.cancel(todo)
        CalendarService.remove(todo)
        context.delete(todo)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
