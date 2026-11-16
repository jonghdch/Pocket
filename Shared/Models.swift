import Foundation
import SwiftData

/// 할 일 하나. 날짜와 시간이 들어가면 일정으로 보인다.
@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var scheduledAt: Date?
    var hasTime: Bool
    var endAt: Date?
    var alertMinutesBefore: Int?
    var estimateMinutes: Int?
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date
    var focusedSeconds: Int
    var calendarEventID: String?
    /// 기간 반복이나 목표 배분으로 함께 만든 할 일끼리 같은 값을 갖는다.
    var seriesID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \Subtask.todo) var subtasks: [Subtask]

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        scheduledAt: Date? = nil,
        hasTime: Bool = false,
        endAt: Date? = nil,
        alertMinutesBefore: Int? = nil,
        estimateMinutes: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.scheduledAt = scheduledAt
        self.hasTime = hasTime
        self.endAt = endAt
        self.alertMinutesBefore = alertMinutesBefore
        self.estimateMinutes = estimateMinutes
        self.isDone = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.focusedSeconds = 0
        self.calendarEventID = nil
        self.seriesID = nil
        self.subtasks = []
    }

    var isEvent: Bool { scheduledAt != nil && hasTime }
    var orderedSubtasks: [Subtask] { subtasks.sorted { $0.order < $1.order } }

    func setDone(_ done: Bool, now: Date = .now) {
        isDone = done
        completedAt = done ? now : nil
    }
}

@Model
final class Subtask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var order: Int
    var todo: TodoItem?

    init(id: UUID = UUID(), title: String, order: Int) {
        self.id = id
        self.title = title
        self.isDone = false
        self.order = order
    }
}

@Model
final class Memo {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var isVoice: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, body: String, isVoice: Bool, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.isVoice = isVoice
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

/// 살 것 하나. 산 뒤 3일이 지나면 지운다.
@Model
final class BuyItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: String?
    var dueDate: Date?
    var store: String?
    var isBought: Bool
    var boughtAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: String? = nil,
        dueDate: Date? = nil,
        store: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.dueDate = dueDate
        self.store = store
        self.isBought = false
        self.boughtAt = nil
        self.createdAt = createdAt
    }

    func setBought(_ bought: Bool, now: Date = .now) {
        isBought = bought
        boughtAt = bought ? now : nil
    }
}

/// 채팅 한 줄. 결과 카드와 나누기 후보는 JSON 으로 함께 저장한다.
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var isMine: Bool
    var text: String
    var createdAt: Date
    var payload: Data?

    init(id: UUID = UUID(), isMine: Bool, text: String, createdAt: Date = .now, payload: Data? = nil) {
        self.id = id
        self.isMine = isMine
        self.text = text
        self.createdAt = createdAt
        self.payload = payload
    }
}

enum PocketStore {
    static let groupID = "group.com.jonghdch.pocket"
    static let schema = Schema([TodoItem.self, Subtask.self, Memo.self, ChatMessage.self, BuyItem.self])

    /// 위젯과 함께 쓰는 위치. App Group 을 못 쓰는 계정이면 nil 이다.
    static var sharedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Pocket.store")
    }

    static var isShared: Bool { sharedURL != nil }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url = sharedURL {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            // 첫 실행에는 폴더가 없어 저장소 생성이 실패할 수 있다.
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
